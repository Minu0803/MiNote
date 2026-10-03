import Foundation

enum LibraryCodec {
    static func decode(_ data: Data) throws -> LibraryCatalog {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw LibraryError.corruptCatalog }
        guard header.version == 1 else { throw LibraryError.unsupportedVersion(header.version) }
        guard let value = try? decoder.decode(LibraryCatalog.self, from: data) else { throw LibraryError.corruptCatalog }
        try validate(value)
        return value
    }
    static func encode(_ catalog: LibraryCatalog) throws -> Data {
        try validate(catalog)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(catalog)
    }
    static func validate(_ catalog: LibraryCatalog) throws {
        guard catalog.version == 1 else { throw LibraryError.unsupportedVersion(catalog.version) }
        guard catalog.revision >= 0 else { throw LibraryError.invalidCatalog("리비전") }
        let folders = Dictionary(catalog.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard folders.count == catalog.folders.count, Set(catalog.notes.map(\.id)).count == catalog.notes.count else {
            throw LibraryError.invalidCatalog("중복 ID")
        }
        for folder in catalog.folders {
            guard !folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.invalidCatalog("빈 폴더 이름") }
            var visited = Set<UUID>(), next: UUID? = folder.id
            while let id = next {
                guard visited.insert(id).inserted else { throw LibraryError.invalidCatalog("폴더 순환 관계") }
                guard let parent = folders[id] else { throw LibraryError.folderMissing }
                next = parent.parentID
            }
        }
        for note in catalog.notes {
            guard note.modifiedAt.isFinite, note.trashedAt?.isFinite != false else { throw LibraryError.invalidCatalog("시각") }
            if let id = note.folderID, folders[id] == nil { throw LibraryError.folderMissing }
        }
    }
}

enum LibraryFiles {
    static func read(_ url: URL) throws -> Data? {
        guard let attributes = try attributes(url) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw POSIXError(.EINVAL) }
        return try Data(contentsOf: url)
    }
    static func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
    static func writeIfAbsent(_ data: Data, to url: URL) throws {
        if let previous = try read(url) {
            guard previous == data else { throw LibraryError.conflict }
        } else { try data.write(to: url, options: .atomic) }
    }
}
