import MiNoteCore
import PencilKit
import XCTest
@testable import MiNote

@MainActor final class CanvasCommandTests: XCTestCase {
    func testBusyDocumentJobBlocksUndoAndRedoCommands() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = EditorSession(store: DocumentStore(directory: directory))
        await session.loadIfNeeded()
        let source = directory.appendingPathComponent("source.pdf")
        try PDFFixture.data(rotations: Array(repeating: 0, count: 500)).write(to: source)
        let canvas = CommandCanvas()
        let reference = CanvasReference(); reference.canvas = canvas
        canvas.drawing = try InkAdapter.decode([testInk()])
        canvas.manager.beginUndoGrouping()
        canvas.manager.registerUndo(withTarget: canvas) { target in
            target.drawing = PKDrawing()
            target.manager.registerUndo(withTarget: target) { $0.drawing = try! InkAdapter.decode([testInk()]) }
        }
        canvas.manager.endUndoGrouping()
        let job = Task { await session.importPDF(from: source) }
        await Task.yield()
        XCTAssertTrue(session.isProcessing, "Commands must be tested during the real import")
        reference.undo(in: session)
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertFalse(canvas.manager.canRedo)
        await job.value
        reference.undo(in: session)
        XCTAssertEqual(canvas.drawing.strokes.count, 0)
        let export = Task { await session.exportPDF() }
        await Task.yield()
        XCTAssertTrue(session.isProcessing, "Redo must be tested during the real export")
        reference.redo(in: session)
        XCTAssertEqual(canvas.drawing.strokes.count, 0)
        _ = await export.value
        reference.redo(in: session)
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
    }
}

@MainActor private final class CommandCanvas: PKCanvasView {
    let manager = UndoManager()
    override var undoManager: UndoManager? { manager }
}
