import Foundation

public struct BackupProgress: Sendable {
    public let completedBytes: Int64
    public let totalBytes: Int64
}
public struct BackupManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let name: String
        public let byteCount: UInt32
        public let crc32: UInt32
    }
    public let archiveVersion: Int
    public let documentID: UUID
    public let schemaVersion: Int
    public let revision: Int64
    public let entries: [Entry]
}
public struct ValidatedBackup: Sendable {
    public let document: NoteDocument
    public let stagingDirectory: URL
    let manifest: BackupManifest

    /// Recheck owned staged bytes immediately before use; validation is not a file-system lock.
    func revalidate() throws {
        for entry in manifest.entries {
            let source = try StoredZIP.fingerprint(name: entry.name, url: stagingDirectory.appendingPathComponent(entry.name))
            guard source.byteCount == entry.byteCount, source.crc32 == entry.crc32 else { throw BackupError.changedSource }
        }
        guard try DocumentCodec.decode(Data(contentsOf: stagingDirectory.appendingPathComponent("document.json"))) == document else {
            throw BackupError.changedSource
        }
    }
}

public actor NoteBackup {
    private let chunkWriter: @Sendable (FileHandle, Data) throws -> Void
    public init() { chunkWriter = { try $0.write(contentsOf: $1) } }
    init(chunkWriter: @escaping @Sendable (FileHandle, Data) throws -> Void) { self.chunkWriter = chunkWriter }

    public func export(document: NoteDocument, assetURLs: [UUID: URL], destination: URL,
                       progress: @Sendable (BackupProgress) -> Void = { _ in }) async throws {
        try Task.checkCancellation(); try DocumentCodec.validate(document)
        guard destination.pathExtension == "minote", Set(assetURLs.keys) == Set(document.pdfAssets.map(\.id)) else {
            throw BackupError.invalidArchive("출력 경로 또는 자산 목록")
        }
        let canonical = destination.resolvingSymlinksInPath().standardizedFileURL
        guard !assetURLs.values.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL == canonical }) else {
            throw BackupError.invalidArchive("원본과 출력 경로가 같습니다")
        }
        if FileManager.default.fileExists(atPath: destination.path) { _ = try StoredZIP.size(destination) }
        let parent = destination.deletingLastPathComponent(), owned = parent.appendingPathComponent(".minote-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: owned) }
        let documentURL = owned.appendingPathComponent("document.json")
        try DocumentCodec.encode(document).write(to: documentURL)
        var sources = [try StoredZIP.fingerprint(name: "document.json", url: documentURL)]
        for asset in document.pdfAssets {
            let source = try StoredZIP.fingerprint(name: asset.relativePath, url: assetURLs[asset.id]!)
            guard source.byteCount == asset.byteCount else { throw DocumentError.missingAsset }; sources.append(source)
        }
        let manifest = BackupManifest(archiveVersion: 1, documentID: document.id, schemaVersion: document.schemaVersion,
                                      revision: document.revision, entries: sources.map { .init(name: $0.name, byteCount: $0.byteCount, crc32: $0.crc32) })
        let manifestURL = owned.appendingPathComponent("manifest.json"), encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL)
        sources.insert(try StoredZIP.fingerprint(name: "manifest.json", url: manifestURL), at: 0)
        let temporary = owned.appendingPathComponent("archive.partial")
        try StoredZIP.write(sources, to: temporary, writer: chunkWriter, progress: progress)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }

    public func validate(source: URL, stagingRoot: URL,
                         progress: @Sendable (BackupProgress) -> Void = { _ in }) async throws -> ValidatedBackup {
        try Task.checkCancellation()
        let entries = try StoredZIP.index(source)
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }),
              let documentEntry = entries.first(where: { $0.name == "document.json" }) else { throw BackupError.invalidArchive("필수 항목 누락") }
        let manifestData = try StoredZIP.read(manifestEntry, from: source, limit: StoredZIP.manifestLimit)
        guard let manifest = try? JSONDecoder().decode(BackupManifest.self, from: manifestData), manifest.archiveVersion == 1 else {
            throw BackupError.invalidArchive("지원하지 않는 manifest")
        }
        let raw = try StoredZIP.read(documentEntry, from: source, limit: StoredZIP.jsonLimit), document = try DocumentCodec.decode(raw)
        let expected = Set(["document.json"] + document.pdfAssets.map(\.relativePath))
        guard manifest.schemaVersion == document.schemaVersion, manifest.documentID == document.id, manifest.revision == document.revision,
              manifest.entries.count == expected.count, Set(manifest.entries.map(\.name)) == expected,
              Set(entries.map(\.name)) == expected.union(["manifest.json"]) else { throw BackupError.invalidArchive("manifest 문서/자산 목록") }
        for item in manifest.entries {
            guard let entry = entries.first(where: { $0.name == item.name }), entry.byteCount == item.byteCount, entry.crc32 == item.crc32 else {
                throw BackupError.invalidArchive("manifest 길이/CRC")
            }
        }
        for asset in document.pdfAssets {
            guard entries.first(where: { $0.name == asset.relativePath })?.byteCount == UInt32(asset.byteCount) else { throw DocumentError.missingAsset }
        }
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let owned = stagingRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        var success = false; defer { if !success { try? FileManager.default.removeItem(at: owned) } }
        try FileManager.default.createDirectory(at: owned.appendingPathComponent("assets"), withIntermediateDirectories: false)
        let total = manifest.entries.reduce(Int64(0)) { $0 + Int64($1.byteCount) }; var completed: Int64 = 0
        for entry in entries where entry.name != "manifest.json" {
            let target = owned.appendingPathComponent(entry.name)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw BackupError.invalidArchive("staging 출력") }
            let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
            try StoredZIP.consume(entry, from: source) { data in
                try output.write(contentsOf: data); completed += Int64(data.count)
                progress(BackupProgress(completedBytes: completed, totalBytes: total))
            }
            try output.synchronize()
        }
        try Task.checkCancellation()
        let result = ValidatedBackup(document: document, stagingDirectory: owned, manifest: manifest)
        try result.revalidate(); success = true; return result
    }
}
