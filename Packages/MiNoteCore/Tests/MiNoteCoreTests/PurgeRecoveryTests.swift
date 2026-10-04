import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class PurgeRecoveryTests: XCTestCase {
    func testOldDocumentStoreCannotRecreatePermanentlyRemovedNote() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root)
        _ = try await library.load(); let id = try await library.createNote(title: "trash")
        let store = try await library.documentStore(for: id), loaded = try await store.load()
        var document = try XCTUnwrap(loaded?.document); document.revision += 1
        try await library.trashNote(id: id); let catalog = try await library.load().catalog
        try await library.purgeTrashedNote(id, expectedCatalogRevision: catalog.revision)
        do { try await store.save(document); XCTFail("stale handle recreated note") } catch { }
        let after = try await LibraryStore(directory: root).load()
        XCTAssertTrue(after.catalog.notes.isEmpty); XCTAssertTrue(after.recoveredNoteIDs.isEmpty)
    }
    func testNotePurgeResumesAtEveryWriteBoundary() async throws {
        for boundary in PurgeBoundary.allCases {
            let root = try LibraryTestSupport.directory(self), good = LibraryStore(directory: root)
            _ = try await good.load(); let keep = try await good.createNote(title: "keep"), remove = try await good.createNote(title: "trash")
            try await good.trashNote(id: remove); let catalog = try await good.load().catalog
            let keepURL = root.appendingPathComponent("notes/\(keep)/document.json"), keepBytes = try Data(contentsOf: keepURL)
            let failing = LibraryStore(directory: root, catalogWriter: { try $0.write(to: $1, options: .atomic) }, purgeCheckpoint: { if $0 == boundary { throw POSIXError(.EIO) } })
            _ = try await failing.load()
            do { try await failing.purgeTrashedNote(remove, expectedCatalogRevision: catalog.revision); XCTFail("interruption \(boundary)") } catch { }
            let reopened = LibraryStore(directory: root), recovered = try await reopened.load(), again = try await reopened.load()
            let committed = boundary.isAfterCatalogCommit
            XCTAssertEqual(recovered.catalog.notes.contains(where: { $0.id == remove }), !committed, "\(boundary)")
            XCTAssertEqual(again.catalog, recovered.catalog); XCTAssertTrue(recovered.recoveredNoteIDs.isEmpty)
            XCTAssertEqual(try Data(contentsOf: keepURL), keepBytes)
            XCTAssertEqual(FileManager.default.fileExists(atPath: root.appendingPathComponent("notes/\(remove)").path), !committed)
            if committed {
                let backup = try LibraryCodec.decode(Data(contentsOf: root.appendingPathComponent("library.backup.json")))
                XCTAssertFalse(backup.notes.contains(where: { $0.id == remove }))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("purge-journal.json").path))
        }
    }
    func testBackupWriteFailureKeepsQuarantineUntilRecoveryAndCannotResurrectNote() async throws {
        let root = try LibraryTestSupport.directory(self), good = LibraryStore(directory: root)
        _ = try await good.load(); let id = try await good.createNote(title: "trash"); try await good.trashNote(id: id)
        let catalog = try await good.load().catalog
        let failing = LibraryStore(directory: root, catalogWriter: { data, url in
            if url.lastPathComponent == "library.backup.json", try !LibraryCodec.decode(data).notes.contains(where: { $0.id == id }) { throw POSIXError(.ENOSPC) }
            try data.write(to: url, options: .atomic)
        })
        _ = try await failing.load()
        do { try await failing.purgeTrashedNote(id, expectedCatalogRevision: catalog.revision); XCTFail("backup error") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("quarantine/\(id)").path))
        do { _ = try await failing.createNote(title: "blocked"); XCTFail("pending operation") } catch { }
        let result = try await LibraryStore(directory: root).load(); XCTAssertTrue(result.catalog.notes.isEmpty); XCTAssertTrue(result.recoveredNoteIDs.isEmpty)
        // Even loss of primary cannot bring this note back from the normal catalog backup.
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("library.json"))
        let fallback = try await LibraryStore(directory: root).load(); XCTAssertTrue(fallback.catalog.notes.isEmpty)
    }
    func testWriteFailureBeforeCommitRestoresOriginalDirectory() async throws {
        for filename in ["purge-journal.json", "library.json"] {
            let root = try LibraryTestSupport.directory(self), good = LibraryStore(directory: root)
            _ = try await good.load(); let id = try await good.createNote(title: "trash"); try await good.trashNote(id: id)
            let catalog = try await good.load().catalog, note = root.appendingPathComponent("notes/\(id)/document.json")
            let bytes = try Data(contentsOf: note), primary = try Data(contentsOf: root.appendingPathComponent("library.json"))
            let failing = LibraryStore(directory: root, catalogWriter: { data, url in
                if url.lastPathComponent == filename { throw POSIXError(.ENOSPC) }
                try data.write(to: url, options: .atomic)
            })
            _ = try await failing.load()
            do { try await failing.purgeTrashedNote(id, expectedCatalogRevision: catalog.revision); XCTFail("write error") } catch { }
            let recovered = try await LibraryStore(directory: root).load()
            XCTAssertEqual(recovered.catalog, catalog); XCTAssertTrue(recovered.recoveredNoteIDs.isEmpty)
            XCTAssertEqual(try Data(contentsOf: note), bytes)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), primary)
        }
    }
    func testActiveStaleOrCorruptJournalNeverDeletesNormalNote() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root)
        _ = try await library.load(); let id = try await library.createNote(title: "keep"), catalog = try await library.load().catalog
        do { try await library.purgeTrashedNote(id, expectedCatalogRevision: catalog.revision); XCTFail("active") } catch { }
        try await library.trashNote(id: id)
        do { try await library.purgeTrashedNote(id, expectedCatalogRevision: catalog.revision); XCTFail("stale") } catch { }
        let note = root.appendingPathComponent("notes/\(id)/document.json"), raw = try Data(contentsOf: note)
        let current = try await library.load().catalog
        let future = Data("{\"version\":2}".utf8)
        try future.write(to: root.appendingPathComponent("library.backup.json"))
        do { try await library.purgeTrashedNote(id, expectedCatalogRevision: current.revision); XCTFail("future backup") }
        catch { XCTAssertEqual(error as? LibraryError, .unsupportedVersion(2)) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.backup.json")), future)
        var committed = current; committed.notes.removeAll(); committed.revision += 1
        let malicious = PurgeJournal(noteID: id, directoryName: "../sentinel", original: current, committed: committed, stage: .prepared)
        try JSONEncoder().encode(malicious).write(to: root.appendingPathComponent("purge-journal.json"))
        do { _ = try await LibraryStore(directory: root).load(); XCTFail("unsafe journal path") } catch { XCTAssertEqual(error as? LibraryError, .invalidPurgeJournal) }
        try Data("{bad journal".utf8).write(to: root.appendingPathComponent("purge-journal.json"))
        do { _ = try await LibraryStore(directory: root).load(); XCTFail("corrupt journal") } catch { XCTAssertEqual(error as? LibraryError, .invalidPurgeJournal) }
        XCTAssertEqual(try Data(contentsOf: note), raw)
    }
}
