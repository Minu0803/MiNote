import XCTest
import PencilKit
import MiNoteCore
@testable import MiNote

@MainActor final class InkUndoTests: XCTestCase {
    func testMoveUsesRealCanvasUndoAndRetainsGenerationAndExactValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DocumentStore(directory:directory)
        let ink = try InkAdapter.encode(PKDrawing(strokes:[sampleStroke()]),preserving:[])
        let original = NoteDocument(title:"undo",pages:[NotePage(strokes:ink)])
        try await store.save(original)
        let session = EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame:CGRect(x:0,y:0,width:834,height:900)); window.rootViewController = UIViewController()
        let canvas = InkCanvasView(frame:window.bounds); window.rootViewController?.view.addSubview(canvas)
        window.makeKeyAndVisible(); canvas.becomeFirstResponder()
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        canvas.drawing = session.drawing
        let manager = try XCTUnwrap(canvas.undoManager)
        manager.removeAllActions()
        let coordinator = InkUndoCoordinator(canvas:canvas,session:session,applyDrawing:{canvas.drawing=$0},onChange:{})
        let polygon:[SelectionPoint] = [.init(x:0,y:0),.init(x:100,y:0),.init(x:100,y:100),.init(x:0,y:100)]
        try session.selectInk(polygon:polygon)
        let generation = session.canvasGeneration
        try coordinator.move(dx:30,dy:-15)
        XCTAssertEqual(session.currentPage?.strokes[0].transform.tx,35)
        XCTAssertEqual(session.document?.revision,1); XCTAssertEqual(session.canvasGeneration,generation)
        manager.undo()
        XCTAssertEqual(session.currentPage?.strokes,ink); XCTAssertEqual(session.document?.revision,2)
        manager.redo()
        XCTAssertEqual(session.currentPage?.strokes[0].transform.tx,35); XCTAssertEqual(session.document?.revision,3)
        XCTAssertEqual(session.currentPage?.strokes[0].id,ink[0].id)
        await session.flush(); XCTAssertEqual(session.saveState,.saved)
    }
    func testSelectionNoopCancelAndRejectedMoveLeaveDocumentUntouched() async throws {
        let store = DocumentStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        session.receiveDrawing(PKDrawing(strokes:[sampleStroke()])); await session.flush()
        let before = try XCTUnwrap(session.document)
        try session.selectInk(polygon:[.init(x:0,y:0),.init(x:100,y:0),.init(x:100,y:100),.init(x:0,y:100)])
        XCTAssertEqual(session.selectedStrokeIDs.count,1)
        XCTAssertNil(try session.translateSelectedInk(dx:0,dy:0)); XCTAssertEqual(session.document,before)
        XCTAssertThrowsError(try session.translateSelectedInk(dx:.nan,dy:0)); XCTAssertEqual(session.document,before)
        session.clearInkSelection(); XCTAssertTrue(session.selectedStrokeIDs.isEmpty)
        XCTAssertNil(try session.translateSelectedInk(dx:10,dy:10)); XCTAssertEqual(session.document,before)
        let overlay = LassoOverlay()
        try session.selectInk(polygon:[.init(x:0,y:0),.init(x:100,y:0),.init(x:100,y:100),.init(x:0,y:100)])
        var committed = 0
        overlay.configure(drawing:session.drawing,portable:before.pages[0].strokes,selectedIDs:session.selectedStrokeIDs,
                          enabled:true,fingerEnabled:true,onSelect:{_ in XCTFail("Cancelled selection")},onMove:{_,_ in committed += 1},onError:{_ in XCTFail("Unexpected error")})
        overlay.begin(at:CGPoint(x:25,y:26))
        overlay.continueGesture(at:CGPoint(x:55,y:11))
        XCTAssertEqual(overlay.previewOffset,CGSize(width:30,height:-15))
        overlay.cancelPreview()
        XCTAssertEqual(overlay.previewOffset,.zero); XCTAssertEqual(committed,0)
        XCTAssertEqual(session.selectedStrokeIDs.count,1); XCTAssertEqual(session.document,before)
    }
}
