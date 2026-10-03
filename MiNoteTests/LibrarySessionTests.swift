import XCTest
import PencilKit
@testable import MiNoteCore
@testable import MiNote

@MainActor final class LibrarySessionTests: XCTestCase {
    private func setupLibrary() async throws -> (URL, LibraryStore, LibrarySession, UUID, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(directory: root); _ = try await store.load()
        let a = try await store.createNote(title: "A"), b = try await store.createNote(title: "B")
        let session = LibrarySession(store: store); await session.load()
        return (root, store, session, a, b)
    }
    func testSwitchAfterEditFlushesOnlyOutgoingNote() async throws {
        let (_, store, session, a, b) = try await setupLibrary()
        await session.openNote(a)
        let outgoing = try XCTUnwrap(session.selectedEditor)
        outgoing.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        await session.openNote(b)
        XCTAssertEqual(session.selectedEditor?.document?.id, b)
        XCTAssertEqual(session.selectedEditor?.strokeCount, 0)
        let savedStore = try await store.documentStore(for: a), saved = try await savedStore.load()
        XCTAssertEqual(saved?.document.pages[0].strokes.count, 1)
        XCTAssertEqual(saved?.document.revision, outgoing.document?.revision)
        await session.openNote(a)
        XCTAssertEqual(session.selectedEditor?.strokeCount, 1)
    }
    func testFailedSaveOrUnsupportedInkBlocksClose() async throws {
        let (root, _, session, a, b) = try await setupLibrary()
        await session.openNote(a)
        let editor = try XCTUnwrap(session.selectedEditor)
        let backup = root.appendingPathComponent("notes/\(a.uuidString)/document.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        let closed = await session.closeNote()
        XCTAssertFalse(closed); XCTAssertTrue(session.selectedEditor === editor); XCTAssertEqual(editor.strokeCount, 1)
        try FileManager.default.removeItem(at: backup)
        editor.retrySave(); await editor.flush()
        XCTAssertEqual(editor.saveState, .saved)
        editor.receiveDrawing(PKDrawing(strokes: [sampleStroke(ink: .pencil)]))
        await session.openNote(b)
        XCTAssertTrue(session.selectedEditor === editor); XCTAssertEqual(editor.strokeCount, 1)
        editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        let retried = await session.closeNote()
        XCTAssertTrue(retried); XCTAssertNil(session.selectedEditor)
    }
    func testRepeatedOpenHasOneActiveSession() async throws {
        let (_, _, session, a, b) = try await setupLibrary()
        await session.openNote(a)
        let original = try XCTUnwrap(session.selectedEditor)
        await session.openNote(a); XCTAssertTrue(session.selectedEditor === original)
        async let first: Void = session.openNote(b)
        async let second: Void = session.openNote(a)
        _ = await (first, second)
        XCTAssertFalse(session.isBusy)
        XCTAssertNotNil(session.selectedEditor?.document)
        let id = try XCTUnwrap(session.selectedEditor?.document?.id)
        XCTAssertTrue([a, b].contains(id))
    }
    func testRenameWaitsUntilEditorIsClosed() async throws {
        let (_, store, session, a, _) = try await setupLibrary()
        await session.openNote(a)
        session.selectedEditor?.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        await session.renameNote(a, title: "Renamed")
        XCTAssertNil(session.selectedEditor)
        let documentStore = try await store.documentStore(for: a), result = try await documentStore.load()
        XCTAssertEqual(result?.document.title, "Renamed"); XCTAssertEqual(result?.document.pages[0].strokes.count, 1)
        XCTAssertEqual(session.notes.first(where: { $0.id == a })?.title, "Renamed")
    }
    func testMissingNoteStaysVisibleAndCannotBecomeBlank() async throws {
        let (root, _, session, a, _) = try await setupLibrary()
        let url = root.appendingPathComponent("notes/\(a.uuidString)/document.json")
        try FileManager.default.removeItem(at: url)
        await session.load()
        XCTAssertNotNil(session.notes.first(where: { $0.id == a })?.error)
        await session.openNote(a)
        XCTAssertNil(session.selectedEditor); XCTAssertNotNil(session.operationError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testDrawingDeliveredDuringCatalogCommitBlocksClose() async throws {
        for unsupported in [false, true] {
            let (root, _, _, a, _) = try await setupLibrary()
            let delivery = LateLibraryDrawing(); delivery.unsupported = unsupported
            let store = LibraryStore(directory: root, catalogWriter: { data, url in
                try data.write(to: url, options: .atomic)
                Task { @MainActor in delivery.deliverOnce() }
            })
            let session = LibrarySession(store: store); await session.load(); await session.openNote(a)
            let editor = try XCTUnwrap(session.selectedEditor); delivery.editor = editor
            editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
            let closed = await session.closeNote()
            XCTAssertFalse(closed, "A late native callback must not lose its editor")
            XCTAssertTrue(session.selectedEditor === editor)
            if unsupported {
                guard case .failed = editor.saveState else { return XCTFail("Unsupported late drawing must block closing") }
            } else {
                XCTAssertEqual(editor.strokeCount, 2)
                let retried = await session.closeNote(); XCTAssertTrue(retried)
                let documentStore = try await store.documentStore(for: a), loaded = try await documentStore.load()
                XCTAssertEqual(loaded?.document.pages[0].strokes.count, 2)
                XCTAssertEqual(loaded?.document.revision, editor.document?.revision)
            }
        }
    }

    func testCatalogFailureAfterFlushKeepsEditorAndCanRetry() async throws {
        let (root, _, _, a, _) = try await setupLibrary()
        let store = LibraryStore(directory: root, catalogWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let session = LibrarySession(store: store); await session.load(); await session.openNote(a)
        let editor = try XCTUnwrap(session.selectedEditor)
        editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        let closed = await session.closeNote()
        XCTAssertFalse(closed); XCTAssertTrue(session.selectedEditor === editor); XCTAssertEqual(editor.saveState, .saved)
        let reopened = LibrarySession(store: LibraryStore(directory: root)); await reopened.load(); await reopened.openNote(a)
        XCTAssertEqual(reopened.selectedEditor?.strokeCount, 1)
    }
}

@MainActor private final class LateLibraryDrawing {
    var editor: EditorSession?
    var unsupported = false
    private var delivered = false
    func deliverOnce() {
        guard !delivered, let editor else { return }
        delivered = true
        let strokes = unsupported ? [sampleStroke(ink: .pencil)] : [sampleStroke(), sampleStroke(offset: 80)]
        editor.receiveDrawing(PKDrawing(strokes: strokes))
    }
}
