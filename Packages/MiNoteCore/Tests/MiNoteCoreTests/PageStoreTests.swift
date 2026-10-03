import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class PageStoreTests: XCTestCase {
    func testMoveDeleteRestoreKeepSelectionAndAllDataAfterReopen() async throws {
        let root = try LibraryTestSupport.directory(self), store = DocumentStore(directory: root)
        let original = NoteDocument.blank(); try await store.save(original)
        let inserted = try await store.applyPageCommand(.insert(after: original.pages[0].id, paper: .grid), expectedRevision: 0)
        let marked = try await store.applyPageCommand(.setBookmark(inserted.pages[1].id, true), expectedRevision: 1)
        let deleted = try await store.applyPageCommand(.delete(marked.pages[1].id), expectedRevision: 2)
        let reopened = DocumentStore(directory: root)
        let loaded = try await reopened.load(); XCTAssertEqual(loaded?.document, deleted)
        let restored = try await reopened.applyPageCommand(.restore(marked.pages[1].id), expectedRevision: 3)
        XCTAssertEqual(restored.pages, marked.pages); XCTAssertEqual(restored.lastOpenedPageID, marked.pages[1].id)
        XCTAssertEqual(restored.revision, 4)
    }

    func testStalePageCommandAndDiskFailureKeepLatestInk() async throws {
        let root = try LibraryTestSupport.directory(self), store = DocumentStore(directory: root)
        var latest = NoteDocument.blank(); try await store.save(latest)
        latest.revision = 1; latest.pages[0].strokes = [fixtureStroke()]; try await store.save(latest)
        let primary = root.appendingPathComponent("document.json"), backup = root.appendingPathComponent("document.backup.json")
        let before = try Data(contentsOf: primary), backupBefore = try Data(contentsOf: backup)
        do { _ = try await store.applyPageCommand(.duplicate(latest.pages[0].id), expectedRevision: 0); XCTFail("Stale") }
        catch { XCTAssertEqual(error as? DocumentError, .staleRevision) }
        XCTAssertEqual(try Data(contentsOf: primary), before); XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
        try FileManager.default.removeItem(at: backup)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        do { _ = try await store.applyPageCommand(.duplicate(latest.pages[0].id), expectedRevision: 1); XCTFail("I/O") } catch {}
        XCTAssertEqual(try Data(contentsOf: primary), before)
        let loaded = try await store.load(); XCTAssertEqual(loaded?.document, latest)
        try FileManager.default.removeItem(at: backup)
        let copied = try await store.applyPageCommand(.duplicate(latest.pages[0].id), expectedRevision: 1)
        XCTAssertEqual(copied.pages[0], latest.pages[0]); XCTAssertEqual(copied.pages.count, 2)
        XCTAssertEqual(try Data(contentsOf: backup), before)
    }
}
