import Foundation

public struct LoadedDocument: Sendable {
    public let document: NoteDocument
    public let recoveredFromBackup: Bool
}

/// One actor owns the single local document. No suspension occurs between revision
/// comparison and replacement, so concurrent save requests cannot interleave writes.
public actor DocumentStore {
    let directory: URL
    private let dataReader: @Sendable (URL) throws -> Data
    private let atomicWriter: @Sendable (Data,URL) throws -> Void
    private var retired = false
    private var primaryURL: URL { directory.appendingPathComponent("document.json") }
    private var backupURL: URL { directory.appendingPathComponent("document.backup.json") }

    public init(directory: URL) {
        self.directory = directory
        self.dataReader = { try Data(contentsOf: $0) }
        self.atomicWriter = { try $0.write(to:$1,options:.atomic) }
    }

    init(directory: URL, dataReader: @escaping @Sendable (URL) throws -> Data) {
        self.directory = directory
        self.dataReader = dataReader
        self.atomicWriter = { try $0.write(to:$1,options:.atomic) }
    }

    init(directory: URL, atomicWriter: @escaping @Sendable (Data,URL) throws -> Void) {
        self.directory=directory; self.dataReader = { try Data(contentsOf:$0) }; self.atomicWriter=atomicWriter
    }

    public func load() throws -> LoadedDocument? {
        guard !retired else { throw DocumentError.documentRemoved }
        do {
            if let primary = try readIfPresent(primaryURL) {
                return LoadedDocument(document: primary, recoveredFromBackup: false)
            }
        } catch let error as DocumentError {
            switch error {
            case .corruptDocument, .invalidDocument:
                break
            case .unsupportedSchema, .staleRevision, .documentConflict, .missingAsset, .documentRemoved:
                throw error
            }
            guard let backup = try readIfPresent(backupURL) else { throw error }
            return LoadedDocument(document: backup, recoveredFromBackup: true)
        }

        if let backup = try readIfPresent(backupURL) {
            return LoadedDocument(document: backup, recoveredFromBackup: true)
        }
        return nil
    }

    public func save(_ document: NoteDocument) throws {
        guard !retired else { throw DocumentError.documentRemoved }
        let data = try DocumentCodec.encode(document)
        for asset in document.pdfAssets { _ = try assetURL(for: asset) }
        let previous = try load()
        if let previous {
            guard document.id == previous.document.id else { throw DocumentError.documentConflict }
            guard document.revision >= previous.document.revision else { throw DocumentError.staleRevision }
            if document.revision == previous.document.revision {
                guard document == previous.document else { throw DocumentError.documentConflict }
                if !previous.recoveredFromBackup, try dataReader(primaryURL) == data { return }
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let previous, !previous.recoveredFromBackup {
            // Foundation's .atomic writes a sibling temporary file, then renames it.
            // Finish the backup first; a failure leaves the current primary untouched.
            try atomicWriter(dataReader(primaryURL),backupURL)
        }
        // A recovered backup is kept intact, rather than replaced with corrupt data.
        try atomicWriter(data,primaryURL)
    }

    func retire() { retired = true }

    public func applyPageCommand(_ command: PageCommand, expectedRevision: Int64) throws -> NoteDocument {
        guard let prior = try load(), prior.document.revision == expectedRevision else { throw DocumentError.staleRevision }
        let updated = try PageCommands.apply(command, to: prior.document)
        try save(updated)
        return updated
    }

    /// The asset is durable before the JSON can reference it. Failure leaves the old
    /// primary intact; an unreferenced asset is harmless and can be collected in M1.
    public func attachPDF(data: Data, asset: PDFAsset, pages: [NotePage], afterPageID: UUID,
                          expectedRevision: Int64) throws -> NoteDocument {
        guard let prior = try load(), prior.document.revision == expectedRevision else { throw DocumentError.staleRevision }
        guard let after = prior.document.pages.firstIndex(where: { $0.id == afterPageID }),
              !prior.document.pdfAssets.contains(where: { $0.id == asset.id }),
              expectedRevision < Int64.max, data.count == asset.byteCount,
              pages.count == asset.pageCount,
              Set(pages.compactMap { $0.pdfSource?.index }) == Set(0..<max(0, asset.pageCount)),
              pages.allSatisfy({ $0.pdfSource?.assetID == asset.id }) else {
            throw DocumentError.invalidDocument("PDF 자산/페이지 매핑/리비전")
        }
        var updated = prior.document
        updated.pdfAssets.append(asset)
        updated.pages.insert(contentsOf: pages, at: after + 1)
        updated.lastOpenedPageID = pages.first?.id
        updated.revision += 1
        try DocumentCodec.validate(updated)
        let assets = directory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(asset.relativePath)
        // A retry may encounter this immutable asset; never replace a different file.
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try dataReader(destination) == data else { throw DocumentError.documentConflict }
        } else {
            try data.write(to: destination, options: .atomic)
        }
        try save(updated)
        return updated
    }

    public func assetURL(for asset: PDFAsset) throws -> URL {
        let url = directory.appendingPathComponent(asset.relativePath)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { throw DocumentError.missingAsset }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == asset.byteCount else { throw DocumentError.missingAsset }
        return url
    }

    private func readIfPresent(_ url: URL) throws -> NoteDocument? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        guard let fileType = attributes[.type] as? FileAttributeType, fileType == .typeRegular else {
            let code: POSIXErrorCode = (attributes[.type] as? FileAttributeType) == .typeDirectory ? .EISDIR : .EINVAL
            throw POSIXError(code)
        }
        let document = try DocumentCodec.decode(dataReader(url))
        for asset in document.pdfAssets { _ = try assetURL(for: asset) }
        return document
    }
}
