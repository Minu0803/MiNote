import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class LibraryBackupTests: XCTestCase {
    func backup(at root: URL) async throws -> ValidatedBackup {
        let helper = NoteBackupTests(), (document, urls) = try helper.fixture(at: root)
        let path = root.appendingPathComponent("note.minote")
        try await NoteBackup().export(document: document, assetURLs: urls, destination: path)
        return try await NoteBackup().validate(source: path, stagingRoot: root.appendingPathComponent("staging"))
    }
    func testRestoreIntoEmptyLibraryAndDuplicateIdentity() async throws {
        let root = try LibraryTestSupport.directory(self), value = try await backup(at: root)
        let libraryRoot = root.appendingPathComponent("library"), library = LibraryStore(directory: libraryRoot)
        _ = try await library.load()
        let folder = try await library.createFolder(name: "Work")
        let first = try await library.restoreBackup(value, folderID: folder)
        XCTAssertEqual(first.id, value.document.id); XCTAssertEqual(first.folderID, folder)
        let originalURL = libraryRoot.appendingPathComponent("notes/\(first.id)/document.json")
        let original = try Data(contentsOf: originalURL)
        let second = try await library.restoreBackup(value, folderID: nil)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        let reopened = LibraryStore(directory: libraryRoot), catalog = try await reopened.load().catalog
        XCTAssertEqual(catalog.notes.count, 2)
        for note in catalog.notes {
            let store = try await reopened.documentStore(for: note.id), result = try await store.load()
            var expected = value.document; expected.id = note.id; expected.title += " (복원)"
            XCTAssertEqual(result?.document, expected)
            for asset in expected.pdfAssets {
                let path = try await store.assetURL(for: asset)
                XCTAssertEqual(try Data(contentsOf: path), try LibraryTestSupport.data("source", extension: "pdf"))
            }
        }
    }
    func testStagingTamperMissingFolderAndCopyFailureCannotChangeExistingNotes() async throws {
        let root = try LibraryTestSupport.directory(self), value = try await backup(at: root)
        let libraryRoot = root.appendingPathComponent("library"), library = LibraryStore(directory: libraryRoot)
        _ = try await library.load(); let existing = try await library.createNote(title: "existing")
        let raw = try Data(contentsOf: libraryRoot.appendingPathComponent("notes/\(existing)/document.json"))
        do { _ = try await library.restoreBackup(value, folderID: UUID()); XCTFail("missing folder") } catch { XCTAssertEqual(error as? LibraryError, .folderMissing) }
        let failing = LibraryStore(directory: libraryRoot, catalogWriter: { try $0.write(to: $1, options: .atomic) }, backupCopier: { _, _ in throw POSIXError(.ENOSPC) })
        _ = try await failing.load()
        do { _ = try await failing.restoreBackup(value, folderID: nil); XCTFail("copy error") } catch { XCTAssertEqual((error as? POSIXError)?.code, .ENOSPC) }
        let path = value.stagingDirectory.appendingPathComponent(value.document.pdfAssets[0].relativePath)
        var altered = try Data(contentsOf: path); altered[0] ^= 1; try altered.write(to: path)
        do { _ = try await library.restoreBackup(value, folderID: nil); XCTFail("tamper") } catch { XCTAssertEqual(error as? BackupError, .changedSource) }
        XCTAssertEqual(try Data(contentsOf: libraryRoot.appendingPathComponent("notes/\(existing)/document.json")), raw)
        let catalog = try await library.load().catalog
        XCTAssertEqual(catalog.notes.map(\.id), [existing])
        try FileManager.default.removeItem(at: path)
        do { _ = try await library.restoreBackup(value, folderID: nil); XCTFail("missing asset") } catch { }
        let cancelled = Task { try await library.restoreBackup(value, folderID: nil) }; cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("cancelled restore") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testCatalogFailureRecoversCompleteOrphanOnce() async throws {
        let root = try LibraryTestSupport.directory(self), value = try await backup(at: root)
        let libraryRoot = root.appendingPathComponent("library"), good = LibraryStore(directory: libraryRoot)
        _ = try await good.load(); let existing = try await good.createNote(title: "existing")
        let before = try Data(contentsOf: libraryRoot.appendingPathComponent("library.json"))
        let failing = LibraryStore(directory: libraryRoot, catalogWriter: { data, url in
            if url.lastPathComponent == "library.json" { throw POSIXError(.ENOSPC) }
            try data.write(to: url, options: .atomic)
        })
        _ = try await failing.load()
        do { _ = try await failing.restoreBackup(value, folderID: nil); XCTFail("catalog error") } catch { XCTAssertEqual((error as? POSIXError)?.code, .ENOSPC) }
        XCTAssertEqual(try Data(contentsOf: libraryRoot.appendingPathComponent("library.json")), before)
        let reopened = LibraryStore(directory: libraryRoot), recovered = try await reopened.load()
        XCTAssertEqual(recovered.recoveredNoteIDs, [value.document.id]); XCTAssertEqual(Set(recovered.catalog.notes.map(\.id)), [existing, value.document.id])
        let next = try await reopened.load()
        XCTAssertEqual(next.recoveredNoteIDs, [])
        let store = try await reopened.documentStore(for: value.document.id)
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.document.pages, value.document.pages)
    }
}
