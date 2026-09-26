import XCTest
import PencilKit
import MiNoteCore
@testable import MiNote

@MainActor final class EditorSessionTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFirstOpenCreatesAndSavesEditableBlankPage() async throws {
        let url = try directory()
        let session = EditorSession(store: DocumentStore(directory: url), saveDelay: .milliseconds(10))
        await session.loadIfNeeded()
        XCTAssertEqual(session.document?.pages.count, 1)
        XCTAssertEqual(session.drawing.strokes.count, 0)
        XCTAssertEqual(session.saveState, .saved)
        let persisted = try await DocumentStore(directory: url).load()
        XCTAssertNotNil(persisted)
    }

    func testDrawingChangesDebounceToLatestRevisionAndRetryFromDisk() async throws {
        let url = try directory()
        let session = EditorSession(store: DocumentStore(directory: url), saveDelay: .milliseconds(40))
        await session.loadIfNeeded()
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        let stroke = sampleStroke(offset: 80)
        session.receiveDrawing(PKDrawing(strokes: [stroke]))
        XCTAssertEqual(session.saveState, .saving)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(session.saveState, .saved)
        let loaded = try await DocumentStore(directory: url).load()
        XCTAssertEqual(loaded?.document.revision, 2)
        XCTAssertEqual(loaded?.document.pages[0].strokes.count, 1)
        XCTAssertEqual(try XCTUnwrap(loaded?.document.pages[0].strokes[0].points[0].y), 100, accuracy: 0.01)
    }

    func testUnsupportedDrawingRemainsInMemoryUntilSupportedEditAndSave() async throws {
        let url = try directory()
        let session = EditorSession(store: DocumentStore(directory: url), saveDelay: .milliseconds(15))
        await session.loadIfNeeded()
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke(ink: .pencil)]))
        XCTAssertEqual(session.drawing.strokes.count, 1)
        guard case .failed = session.saveState else { return XCTFail("Unsupported drawing must display a failure") }
        let existing = try await DocumentStore(directory: url).load()
        XCTAssertEqual(existing?.document.pages[0].strokes.count, 0)
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(session.saveState, .saved)
        let recovered = try await DocumentStore(directory: url).load()
        XCTAssertEqual(recovered?.document.pages[0].strokes.count, 1)
    }

    func testFailedWriteKeepsDrawingVisibleAndManualRetrySavesIt() async throws {
        let url = try directory()
        let session = EditorSession(store: DocumentStore(directory: url), saveDelay: .milliseconds(20))
        await session.loadIfNeeded()
        let backup = url.appendingPathComponent("document.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        try await Task.sleep(for: .milliseconds(150))
        guard case .failed = session.saveState else { return XCTFail("Write failure must be visible") }
        XCTAssertEqual(session.drawing.strokes.count, 1)
        let savedBeforeRetry = try await DocumentStore(directory: url).load()
        XCTAssertEqual(savedBeforeRetry?.document.pages[0].strokes.count, 0)
        try FileManager.default.removeItem(at: backup)
        session.retrySave()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(session.saveState, .saved)
        let savedAfterRetry = try await DocumentStore(directory: url).load()
        XCTAssertEqual(savedAfterRetry?.document.pages[0].strokes.count, 1)
    }

    func testMissingRecoveryFilesBlockEditingAndCanRetryAfterExternalRepair() async throws {
        let url = try directory()
        let bad = url.appendingPathComponent("document.json")
        try Data("invalid".utf8).write(to: bad)
        let session = EditorSession(store: DocumentStore(directory: url), saveDelay: .milliseconds(10))
        await session.loadIfNeeded()
        XCTAssertNil(session.document)
        XCTAssertNotNil(session.loadError)
        try FileManager.default.removeItem(at: bad)
        try DocumentCodec.encode(.blank()).write(to: bad)
        await session.retryLoad()
        XCTAssertNotNil(session.document)
        XCTAssertNil(session.loadError)
    }
}
