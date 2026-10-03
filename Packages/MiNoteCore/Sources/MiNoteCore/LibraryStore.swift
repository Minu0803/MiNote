import Foundation

/// One library actor owns a catalog and one DocumentStore per note directory.
public actor LibraryStore {
    let directory: URL
    var catalog: LibraryCatalog?
    var busy = false
    var stores: [UUID: DocumentStore] = [:]
    var locations: [UUID: URL] = [:]
    let catalogWriter: @Sendable (Data, URL) throws -> Void
    var primaryURL: URL { directory.appendingPathComponent("library.json") }
    var backupURL: URL { directory.appendingPathComponent("library.backup.json") }
    var notesURL: URL { directory.appendingPathComponent("notes", isDirectory: true) }

    public init(directory: URL) {
        self.directory = directory
        self.catalogWriter = { try $0.write(to: $1, options: .atomic) }
    }
    init(directory: URL, catalogWriter: @escaping @Sendable (Data, URL) throws -> Void) {
        self.directory = directory; self.catalogWriter = catalogWriter
    }

    public func load() async throws -> LibraryLoadResult {
        guard !busy else { throw LibraryError.busy }
        busy = true; defer { busy = false }
        let disk = try readCatalog()
        var value = disk?.value ?? LibraryCatalog()
        var notices: [String] = []
        if disk?.recovered == true { notices.append("라이브러리를 복구본에서 복원했습니다.") }
        if disk == nil, let legacy = try await migrateLegacy() {
            value.notes.append(legacy)
            notices.append("기존 노트와 PDF를 라이브러리로 옮겼습니다. 기존 원본은 보존됩니다.")
        }
        let found = try discoverDirectories()
        var recovered: [UUID] = []
        for (id, url) in found.sorted(by: { $0.key.uuidString < $1.key.uuidString }) where !value.notes.contains(where: { $0.id == id }) {
            let date = try LibraryFiles.attributes(url)?[.modificationDate] as? Date
            value.notes.append(LibraryNote(id: id, modifiedAt: date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970))
            recovered.append(id)
        }
        if !recovered.isEmpty { notices.append("목록에 연결되지 않은 노트 \(recovered.count)개를 복구했습니다. 오류가 있는 노트도 원본을 보존합니다.") }
        if disk == nil || value != disk?.value || disk?.recovered == true {
            if disk != nil, value != disk?.value {
                guard value.revision < Int64.max else { throw LibraryError.invalidCatalog("리비전 한도") }
                value.revision += 1
            }
            try writeCatalog(value, expected: disk?.value)
        }
        catalog = value; locations = found
        return LibraryLoadResult(catalog: value, recoveredNoteIDs: recovered,
            recoveryNotice: notices.isEmpty ? nil : notices.joined(separator: " "))
    }

    public func documentStore(for id: UUID) throws -> DocumentStore {
        guard let catalog else { throw LibraryError.notLoaded }
        guard catalog.notes.contains(where: { $0.id == id }) else { throw LibraryError.noteMissing(id) }
        let url = noteDirectory(id)
        // A referenced missing note is an error, never a request for a new blank.
        guard try LibraryFiles.attributes(url.appendingPathComponent("document.json")) != nil ||
                  LibraryFiles.attributes(url.appendingPathComponent("document.backup.json")) != nil else {
            throw LibraryError.documentMissing(id)
        }
        return store(for: id)
    }

    func noteDirectory(_ id: UUID) -> URL { locations[id] ?? notesURL.appendingPathComponent(id.uuidString, isDirectory: true) }
    func store(for id: UUID) -> DocumentStore {
        if let existing = stores[id] { return existing }
        let result = DocumentStore(directory: noteDirectory(id)); stores[id] = result
        return result
    }

    struct DiskCatalog { let value: LibraryCatalog; let raw: Data; let recovered: Bool }
    func readCatalog() throws -> DiskCatalog? {
        do {
            if let raw = try LibraryFiles.read(primaryURL) {
                return DiskCatalog(value: try LibraryCodec.decode(raw), raw: raw, recovered: false)
            }
        } catch let error as LibraryError {
            guard error == .corruptCatalog else { throw error }
            guard let raw = try LibraryFiles.read(backupURL) else { throw error }
            return DiskCatalog(value: try LibraryCodec.decode(raw), raw: raw, recovered: true)
        }
        if let raw = try LibraryFiles.read(backupURL) {
            return DiskCatalog(value: try LibraryCodec.decode(raw), raw: raw, recovered: true)
        }
        return nil
    }
    func writeCatalog(_ value: LibraryCatalog, expected: LibraryCatalog?) throws {
        let data = try LibraryCodec.encode(value), actual = try readCatalog()
        guard actual?.value == expected else { throw LibraryError.conflict }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let actual, !actual.recovered { try catalogWriter(actual.raw, backupURL) }
        try catalogWriter(data, primaryURL)
    }
    func commit(_ value: LibraryCatalog) throws {
        guard let prior = catalog else { throw LibraryError.notLoaded }
        var updated = value
        guard prior.revision < Int64.max else { throw LibraryError.invalidCatalog("리비전 한도") }
        updated.revision = prior.revision + 1
        try writeCatalog(updated, expected: prior)
        catalog = updated
    }

    private func discoverDirectories() throws -> [UUID: URL] {
        guard let attributes = try LibraryFiles.attributes(notesURL) else { return [:] }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw POSIXError(.ENOTDIR) }
        var result: [UUID: URL] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: notesURL, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            guard try LibraryFiles.attributes(url)?[.type] as? FileAttributeType == .typeDirectory else { throw POSIXError(.ENOTDIR) }
            guard result[id] == nil else { throw LibraryError.invalidCatalog("중복 노트 디렉터리") }
            result[id] = url
        }
        return result
    }

    private func migrateLegacy() async throws -> LibraryNote? {
        let source = DocumentStore(directory: directory)
        guard let loaded = try await source.load() else { return nil }
        let document = loaded.document
        let destination = notesURL.appendingPathComponent(document.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for asset in document.pdfAssets {
            let assetURL = try await source.assetURL(for: asset)
            try FileManager.default.createDirectory(at: destination.appendingPathComponent("assets"), withIntermediateDirectories: true)
            try LibraryFiles.writeIfAbsent(Data(contentsOf: assetURL), to: destination.appendingPathComponent(asset.relativePath))
        }
        // Retain raw backup/v1 bytes, and commit a usable primary last.
        if let backup = try LibraryFiles.read(directory.appendingPathComponent("document.backup.json")) {
            try LibraryFiles.writeIfAbsent(backup, to: destination.appendingPathComponent("document.backup.json"))
        }
        let sourceFile = loaded.recoveredFromBackup ? "document.backup.json" : "document.json"
        guard let raw = try LibraryFiles.read(directory.appendingPathComponent(sourceFile)) else { throw LibraryError.conflict }
        if try LibraryFiles.read(destination.appendingPathComponent("document.json")) == nil {
            try raw.write(to: destination.appendingPathComponent("document.json"), options: .atomic)
        }
        let copied = try await DocumentStore(directory: destination).load()
        guard copied?.document.id == document.id else { throw LibraryError.conflict }
        let date = try LibraryFiles.attributes(directory.appendingPathComponent(sourceFile))?[.modificationDate] as? Date
        return LibraryNote(id: document.id, modifiedAt: date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
    }
}

extension LibraryStore {
    public func createNote(title: String, folderID: UUID? = nil) async throws -> UUID {
        var value = try readyCatalog()
        let title = try nonempty(title)
        try checkFolder(folderID, in: value)
        busy = true; defer { busy = false }
        let document = NoteDocument(title: title, pages: [NotePage()])
        try await store(for: document.id).save(document)
        value.notes.append(LibraryNote(id: document.id, folderID: folderID, modifiedAt: Date().timeIntervalSince1970))
        try commit(value)
        return document.id
    }

    public func renameNote(id: UUID, title: String) async throws {
        var value = try readyCatalog()
        let index = try noteIndex(id, in: value), title = try nonempty(title)
        guard value.notes[index].trashedAt == nil else { throw LibraryError.noteTrashed }
        let store = try documentStore(for: id)
        busy = true; defer { busy = false }
        guard var document = try await store.load()?.document else { throw LibraryError.documentMissing(id) }
        guard document.id == id else { throw LibraryError.conflict }
        guard document.revision < Int64.max else { throw LibraryError.invalidCatalog("리비전 한도") }
        document.title = title; document.revision += 1
        try await store.save(document)
        value.notes[index].modifiedAt = Date().timeIntervalSince1970
        try commit(value)
    }

    public func createFolder(name: String, parentID: UUID? = nil) throws -> UUID {
        var value = try readyCatalog()
        try checkFolder(parentID, in: value)
        let folder = LibraryFolder(name: try nonempty(name), parentID: parentID)
        value.folders.append(folder); try commit(value)
        return folder.id
    }
    public func renameFolder(id: UUID, name: String) throws {
        var value = try readyCatalog()
        guard let index = value.folders.firstIndex(where: { $0.id == id }) else { throw LibraryError.folderMissing }
        value.folders[index].name = try nonempty(name); try commit(value)
    }
    public func moveFolder(id: UUID, parentID: UUID?) throws {
        var value = try readyCatalog()
        try checkFolder(parentID, in: value)
        guard let index = value.folders.firstIndex(where: { $0.id == id }) else { throw LibraryError.folderMissing }
        value.folders[index].parentID = parentID; try commit(value)
    }
    public func moveNote(id: UUID, folderID: UUID?) throws {
        var value = try readyCatalog()
        try checkFolder(folderID, in: value)
        let index = try noteIndex(id, in: value)
        guard value.notes[index].trashedAt == nil else { throw LibraryError.noteTrashed }
        value.notes[index].folderID = folderID; try commit(value)
    }
    public func trashNote(id: UUID) throws {
        var value = try readyCatalog(), index: Int
        index = try noteIndex(id, in: value)
        value.notes[index].trashedAt = Date().timeIntervalSince1970; try commit(value)
    }
    public func restoreNote(id: UUID) throws {
        var value = try readyCatalog(), index: Int
        index = try noteIndex(id, in: value)
        value.notes[index].trashedAt = nil; try commit(value)
    }
    public func markModified(id: UUID, at: Double) throws {
        var value = try readyCatalog()
        let index = try noteIndex(id, in: value)
        value.notes[index].modifiedAt = at; try commit(value)
    }
    private func readyCatalog() throws -> LibraryCatalog {
        guard !busy else { throw LibraryError.busy }
        guard let catalog else { throw LibraryError.notLoaded }
        return catalog
    }
    private func nonempty(_ text: String) throws -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LibraryError.invalidCatalog("이름을 입력해 주세요") }
        return result
    }
    private func noteIndex(_ id: UUID, in value: LibraryCatalog) throws -> Int {
        guard let index = value.notes.firstIndex(where: { $0.id == id }) else { throw LibraryError.noteMissing(id) }
        return index
    }
    private func checkFolder(_ id: UUID?, in value: LibraryCatalog) throws {
        if let id, !value.folders.contains(where: { $0.id == id }) { throw LibraryError.folderMissing }
    }
}
