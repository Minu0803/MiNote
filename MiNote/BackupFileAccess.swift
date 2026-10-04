import Foundation
import MiNoteCore

actor BackupFileAccess {
    func prepare(url: URL, progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }) async throws -> ValidatedBackup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent("MiNote-Backup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: owned) }
        let local = owned.appendingPathComponent("source.minote")
        var result: Result<Void, Error>?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result { try Self.copy(coordinated, to: local, progress: progress) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BackupError.invalidArchive("파일 접근") }; try result.get()
        let backup = try await NoteBackup().validate(source: local, stagingRoot: FileManager.default.temporaryDirectory.appendingPathComponent("MiNote-Backup-Staging"), progress: progress)
        var success = false; defer { if !success { try? FileManager.default.removeItem(at: backup.stagingDirectory) } }
        for asset in backup.document.pdfAssets {
            try Task.checkCancellation()
            _ = try PDFValidation.open(url: backup.stagingDirectory.appendingPathComponent(asset.relativePath), asset: asset,
                referencedPages: (backup.document.pages + backup.document.deletedPages.map(\.page)).filter { $0.pdfSource?.assetID == asset.id })
        }
        try Task.checkCancellation(); success = true; return backup
    }
    func removeStaging(_ backup: ValidatedBackup) { try? FileManager.default.removeItem(at: backup.stagingDirectory) }
    private static func copy(_ source: URL, to destination: URL, progress: @Sendable (BackupProgress) -> Void) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, let bytes = attrs[.size] as? NSNumber else { throw BackupError.invalidArchive("일반 파일이 아닙니다") }
        let total = bytes.int64Value
        guard total >= 0, total <= 640 * 1024 * 1024 else { throw BackupError.limitExceeded }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw BackupError.invalidArchive("임시 파일") }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }; var completed: Int64 = 0
        while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
            try Task.checkCancellation(); completed += Int64(data.count)
            guard completed <= total else { throw BackupError.changedSource }
            try output.write(contentsOf: data); progress(.init(completedBytes: completed, totalBytes: total))
        }
        guard completed == total else { throw BackupError.changedSource }; try output.synchronize()
    }
}
