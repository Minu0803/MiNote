import Foundation

public struct LoadedDocument: Sendable {
    public let document: NoteDocument
    public let recoveredFromBackup: Bool
}

/// One actor owns the single local document. No suspension occurs between revision
/// comparison and replacement, so concurrent save requests cannot interleave writes.
public actor DocumentStore {
    private let directory: URL
    private let dataReader: @Sendable (URL) throws -> Data
    private var primaryURL: URL { directory.appendingPathComponent("document.json") }
    private var backupURL: URL { directory.appendingPathComponent("document.backup.json") }

    public init(directory: URL) {
        self.directory = directory
        self.dataReader = { try Data(contentsOf: $0) }
    }

    init(directory: URL, dataReader: @escaping @Sendable (URL) throws -> Data) {
        self.directory = directory
        self.dataReader = dataReader
    }

    public func load() throws -> LoadedDocument? {
        do {
            if let primary = try readIfPresent(primaryURL) {
                return LoadedDocument(document: primary, recoveredFromBackup: false)
            }
        } catch let error as DocumentError {
            switch error {
            case .corruptDocument, .invalidDocument:
                break
            case .unsupportedSchema, .staleRevision, .documentConflict:
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
        let data = try DocumentCodec.encode(document)
        let previous = try load()
        if let previous {
            guard document.id == previous.document.id else { throw DocumentError.documentConflict }
            guard document.revision >= previous.document.revision else { throw DocumentError.staleRevision }
            if document.revision == previous.document.revision {
                guard document == previous.document else { throw DocumentError.documentConflict }
                if !previous.recoveredFromBackup { return }
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let previous, !previous.recoveredFromBackup {
            // Foundation's .atomic writes a sibling temporary file, then renames it.
            // Finish the backup first; a failure leaves the current primary untouched.
            try DocumentCodec.encode(previous.document).write(to: backupURL, options: .atomic)
        }
        // A recovered backup is kept intact, rather than replaced with corrupt data.
        try data.write(to: primaryURL, options: .atomic)
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
        return try DocumentCodec.decode(dataReader(url))
    }
}
