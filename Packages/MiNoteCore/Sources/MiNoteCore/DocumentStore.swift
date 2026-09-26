import Foundation

public struct LoadedDocument: Sendable {
    public let document: NoteDocument
    public let recoveredFromBackup: Bool
}

/// One actor owns the single local document. No suspension occurs between revision
/// comparison and replacement, so concurrent save requests cannot interleave writes.
public actor DocumentStore {
    private let directory: URL
    private var primaryURL: URL { directory.appendingPathComponent("document.json") }
    private var backupURL: URL { directory.appendingPathComponent("document.backup.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> LoadedDocument? {
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            do {
                return LoadedDocument(document: try read(primaryURL), recoveredFromBackup: false)
            } catch DocumentError.unsupportedSchema(let version) {
                // Never downgrade a document written by a newer application.
                throw DocumentError.unsupportedSchema(version)
            } catch {
                guard FileManager.default.fileExists(atPath: backupURL.path) else { throw error }
                return LoadedDocument(document: try read(backupURL), recoveredFromBackup: true)
            }
        }
        if FileManager.default.fileExists(atPath: backupURL.path) {
            return LoadedDocument(document: try read(backupURL), recoveredFromBackup: true)
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

    private func read(_ url: URL) throws -> NoteDocument {
        try DocumentCodec.decode(Data(contentsOf: url))
    }
}
