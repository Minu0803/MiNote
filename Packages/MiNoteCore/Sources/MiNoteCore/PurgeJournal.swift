import Foundation

enum PurgeBoundary: String, CaseIterable, Sendable {
    case prepared, quarantined, catalogPrimary, catalogBackup, catalogCommitted, removed, finished
    var isAfterCatalogCommit: Bool { self != .prepared && self != .quarantined }
}
struct PurgeJournal: Codable {
    enum Stage: String, Codable { case prepared, catalogCommitted, finished }
    var version = 1
    let noteID: UUID
    let directoryName: String
    let original: LibraryCatalog
    let committed: LibraryCatalog
    var stage: Stage
    func validate() throws {
        guard version == 1, UUID(uuidString: directoryName) == noteID,
              original.revision < Int64.max,
              original.notes.first(where: { $0.id == noteID })?.trashedAt != nil else { throw LibraryError.invalidPurgeJournal }
        try LibraryCodec.validate(original); try LibraryCodec.validate(committed)
        var expected = original; expected.notes.removeAll { $0.id == noteID }; expected.revision += 1
        guard expected == committed else { throw LibraryError.invalidPurgeJournal }
    }
}

extension LibraryStore {
    private var journalURL: URL { directory.appendingPathComponent("purge-journal.json") }
    private var quarantineURL: URL { directory.appendingPathComponent("quarantine") }
    private func writeJournal(_ journal: PurgeJournal) throws {
        try journal.validate(); let data = try JSONEncoder().encode(journal)
        guard data.count <= 16 * 1024 * 1024 else { throw LibraryError.invalidPurgeJournal }
        try catalogWriter(data, journalURL)
    }
    public func purgeTrashedNote(_ id: UUID, expectedCatalogRevision: Int64) async throws {
        let original = try readyCatalog(), index = try noteIndex(id, in: original)
        guard original.revision == expectedCatalogRevision else { throw LibraryError.conflict }
        guard original.notes[index].trashedAt != nil else { throw LibraryError.invalidCatalog("휴지통 노트만 영구 삭제할 수 있습니다") }
        guard original.revision < Int64.max else { throw LibraryError.invalidCatalog("리비전 한도") }
        guard try readCatalog()?.value == original else { throw LibraryError.conflict }
        if let backup = try LibraryFiles.read(backupURL) { _ = try LibraryCodec.decode(backup) }
        guard try LibraryFiles.attributes(journalURL) == nil else { throw LibraryError.invalidPurgeJournal }
        try requireDirectory(notesURL); let noteURL = noteDirectory(id); try requireDirectory(noteURL)
        if try LibraryFiles.attributes(quarantineURL) == nil { try FileManager.default.createDirectory(at: quarantineURL, withIntermediateDirectories: false) }
        try requireDirectory(quarantineURL)
        let quarantine = quarantineURL.appendingPathComponent(id.uuidString)
        guard try LibraryFiles.attributes(quarantine) == nil else { throw LibraryError.invalidPurgeJournal }
        var committed = original; committed.notes.remove(at: index); committed.revision += 1
        var journal = PurgeJournal(noteID: id, directoryName: noteURL.lastPathComponent, original: original, committed: committed, stage: .prepared)
        busy = true; defer { busy = false }
        let oldStore = store(for: id)
        await oldStore.retire(); stores[id] = nil
        do {
            guard try readCatalog()?.value == original else { throw LibraryError.conflict }
            try writeJournal(journal); try purgeCheckpoint(.prepared)
            try FileManager.default.moveItem(at: noteURL, to: quarantine); try purgeCheckpoint(.quarantined)
            // Primary is the commit decision. Recovery inspects it even if journal stage is still prepared.
            let encoded = try LibraryCodec.encode(committed)
            try catalogWriter(encoded, primaryURL); try purgeCheckpoint(.catalogPrimary)
            try catalogWriter(encoded, backupURL); try purgeCheckpoint(.catalogBackup)
            journal.stage = .catalogCommitted; try writeJournal(journal); try purgeCheckpoint(.catalogCommitted)
            try FileManager.default.removeItem(at: quarantine); try purgeCheckpoint(.removed)
            journal.stage = .finished; try writeJournal(journal); try purgeCheckpoint(.finished)
            try FileManager.default.removeItem(at: journalURL)
            catalog = committed; locations[id] = nil; stores[id] = nil
        } catch {
            // Caller must load/recover before further edits; the durable journal remains authoritative.
            catalog = nil; throw error
        }
    }

    func recoverPurgeIfNeeded() throws {
        guard try LibraryFiles.attributes(journalURL) != nil else { return }
        guard try StoredZIP.size(journalURL) <= 16 * 1024 * 1024,
              let raw = try LibraryFiles.read(journalURL), var journal = try? JSONDecoder().decode(PurgeJournal.self, from: raw) else {
            throw LibraryError.invalidPurgeJournal
        }
        do { try journal.validate() } catch { throw LibraryError.invalidPurgeJournal }
        try requireDirectory(notesURL); try requireDirectory(quarantineURL)
        let originalURL = notesURL.appendingPathComponent(journal.directoryName), quarantined = quarantineURL.appendingPathComponent(journal.noteID.uuidString)
        let hasOriginal = try LibraryFiles.attributes(originalURL) != nil, hasQuarantine = try LibraryFiles.attributes(quarantined) != nil
        guard !(hasOriginal && hasQuarantine) else { throw LibraryError.invalidPurgeJournal }
        if hasOriginal { try requireDirectory(originalURL) }; if hasQuarantine { try requireDirectory(quarantined) }
        guard let primary = try LibraryFiles.read(primaryURL), let current = try? LibraryCodec.decode(primary) else { throw LibraryError.invalidPurgeJournal }
        if current == journal.original, journal.stage == .prepared {
            guard hasOriginal || hasQuarantine else { throw LibraryError.invalidPurgeJournal }
            if hasQuarantine { try FileManager.default.moveItem(at: quarantined, to: originalURL) }
            try FileManager.default.removeItem(at: journalURL)
        } else if current == journal.committed {
            if let backup = try LibraryFiles.read(backupURL) { _ = try LibraryCodec.decode(backup) }
            let encoded = try LibraryCodec.encode(journal.committed)
            // Never delete bytes until the fallback catalog also excludes the target.
            try catalogWriter(encoded, backupURL)
            journal.stage = .catalogCommitted; try writeJournal(journal)
            if hasOriginal { try FileManager.default.moveItem(at: originalURL, to: quarantined) }
            if hasOriginal || hasQuarantine { try FileManager.default.removeItem(at: quarantined) }
            journal.stage = .finished; try writeJournal(journal)
            try FileManager.default.removeItem(at: journalURL)
        } else { throw LibraryError.invalidPurgeJournal }
        locations[journal.noteID] = nil; stores[journal.noteID] = nil
    }
}
