import Foundation

public struct MaintenanceReport: Sendable {
    public struct Item: Sendable, Identifiable {
        public var id: String { url.path }
        public let url: URL
        public let byteCount: Int64
        public let protectionReason: String?
    }
    public var items: [Item] = []
    public var removedURLs: [URL] = []
    public var candidates: [Item] {
        let removed = Set(removedURLs)
        return items.filter { $0.protectionReason == nil && !removed.contains($0.url) }
    }
    public var protectedItems: [Item] { items.filter { $0.protectionReason != nil } }
    public var candidateBytes: Int64 { candidates.reduce(0) { $0 + $1.byteCount } }
}

extension LibraryStore {
    public func maintenanceReport() async throws -> MaintenanceReport { try await maintain(clean: false) }
    public func cleanUnreferencedFiles() async throws -> MaintenanceReport { try await maintain(clean: true) }
    private func maintain(clean: Bool) async throws -> MaintenanceReport {
        let value = try readyCatalog()
        busy = true; defer { busy = false }
        var report = MaintenanceReport()
        // A prefix alone is not proof of ownership. Report possible interrupted
        // restores, but preserve their contents until durable ownership exists.
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = url.lastPathComponent
            guard name.hasPrefix(".restore-"), let id = UUID(uuidString: String(name.dropFirst(9))),
                  name == ".restore-" + id.uuidString else { continue }
            report.items.append(.init(url: url, byteCount: 0,
                protectionReason: "중단된 복원으로 남았을 수 있는 파일이 있습니다. 소유권을 확인할 수 없어 보존했습니다."))
        }
        for note in value.notes {
            try Task.checkCancellation()
            let result = await store(for: note.id).assetMaintenance(expectedID: note.id, clean: clean)
            report.items += result.items; report.removedURLs += result.removedURLs
        }
        return report
    }
    public func purgeDeletedPages(_ ids: [UUID], noteID: UUID, expectedRevision: Int64) async throws -> NoteDocument {
        let value = try readyCatalog(), index = try noteIndex(noteID, in: value)
        guard value.notes[index].trashedAt == nil else { throw LibraryError.noteTrashed }
        let store = try documentStore(for: noteID)
        busy = true; defer { busy = false }
        return try await store.purgeDeletedPages(ids, documentID: noteID, expectedRevision: expectedRevision)
    }
}

extension DocumentStore {
    /// Runs on the same actor as attach/save: candidates cannot race a new asset commit.
    func assetMaintenance(expectedID: UUID, clean: Bool) -> MaintenanceReport {
        var result = MaintenanceReport()
        do {
            try requireDirectory(directory)
            var references = Set<UUID>(), snapshotCount = 0
            for name in ["document.json", "document.backup.json"] {
                let url = directory.appendingPathComponent(name)
                guard try LibraryFiles.attributes(url) != nil else { continue }
                guard try StoredZIP.size(url) <= StoredZIP.jsonLimit else { throw BackupError.limitExceeded }
                guard let raw = try LibraryFiles.read(url) else { throw DocumentError.corruptDocument }
                let document = try DocumentCodec.decode(raw)
                guard document.id == expectedID else { throw DocumentError.documentConflict }
                for asset in document.pdfAssets { _ = try assetURL(for: asset); references.insert(asset.id) }
                snapshotCount += 1
            }
            guard snapshotCount > 0 else { throw LibraryError.documentMissing(expectedID) }
            let assets = directory.appendingPathComponent("assets")
            guard try LibraryFiles.attributes(assets) != nil else { return result }
            try requireDirectory(assets)
            for url in try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                guard url.pathExtension == "pdf", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      url.lastPathComponent == id.uuidString + ".pdf" else { continue }
                let bytes = try StoredZIP.size(url)
                let reason = references.contains(id) ? "현재 문서 또는 정상 복구본에서 사용 중" : nil
                result.items.append(.init(url: url, byteCount: Int64(bytes), protectionReason: reason))
                if clean, reason == nil { try Task.checkCancellation(); try FileManager.default.removeItem(at: url); result.removedURLs.append(url) }
            }
        } catch {
            result.items.append(.init(url: directory, byteCount: 0, protectionReason: "정리를 보류했습니다: " + error.localizedDescription))
        }
        return result
    }
    func purgeDeletedPages(_ ids: [UUID], documentID: UUID, expectedRevision: Int64) throws -> NoteDocument {
        try Task.checkCancellation()
        guard let prior = try load(), prior.document.revision == expectedRevision else { throw DocumentError.staleRevision }
        var document = prior.document
        guard document.id == documentID else { throw DocumentError.documentConflict }
        let selected = Set(ids)
        guard !selected.isEmpty, selected.count == ids.count, selected.isSubset(of: Set(document.deletedPages.map(\.id))),
              document.revision < Int64.max else { throw DocumentError.invalidDocument("삭제 보관 페이지를 선택해 주세요") }
        let removedAssets = Set(document.deletedPages.filter { selected.contains($0.id) }.compactMap { $0.page.pdfSource?.assetID })
        document.deletedPages.removeAll { selected.contains($0.id) }
        let retainedAssets = Set((document.pages + document.deletedPages.map(\.page)).compactMap { $0.pdfSource?.assetID })
        document.pdfAssets.removeAll { removedAssets.contains($0.id) && !retainedAssets.contains($0.id) }
        document.revision += 1
        try save(document); return document
    }
}

func requireDirectory(_ url: URL) throws {
    guard try LibraryFiles.attributes(url)?[.type] as? FileAttributeType == .typeDirectory else { throw POSIXError(.ENOTDIR) }
}
