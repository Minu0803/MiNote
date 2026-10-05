import XCTest
import PencilKit
import MiNoteCore
@testable import MiNote

@MainActor final class InkUndoTests: XCTestCase {
    private func selectionBox(_ session: EditorSession, x: Double = 0, y: Double = 0, size: Double = 1000) throws {
        try session.selectInk(polygon:[.init(x:x,y:y),.init(x:x+size,y:y),.init(x:x+size,y:y+size),.init(x:x,y:y+size)])
    }
    func testDuplicateDeleteRepeatedCloneNativeEditsAndUndoKeepExactIdentities() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=DocumentStore(directory:root), session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let c=NoteCanvas.Coordinator(session:session,reference:reference); c.attach(to:canvas)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke(),sampleStroke()]),to:canvas); c.canvasViewDrawingDidChange(canvas)
        let original=try XCTUnwrap(session.currentPage?.strokes)
        try selectionBox(session); reference.duplicateSelectedInk(in:session)
        let once=try XCTUnwrap(session.currentPage?.strokes)
        XCTAssertEqual(once.count,4); XCTAssertEqual(Array(once.prefix(2)),original)
        XCTAssertEqual(session.selectedStrokeIDs,Set(once.suffix(2).map(\.id)))
        reference.duplicateSelectedInk(in:session)
        let twice=try XCTUnwrap(session.currentPage?.strokes)
        XCTAssertEqual(twice.count,6); XCTAssertEqual(Set(twice.map(\.id)).count,6)
        XCTAssertEqual(twice[4].transform.tx,45); XCTAssertEqual(twice[4].transform.ty,46)
        reference.deleteSelectedInk(in:session)
        XCTAssertEqual(session.currentPage?.strokes,once); XCTAssertTrue(session.selectedStrokeIDs.isEmpty)
        canvas.undoManager?.undo(); XCTAssertEqual(session.currentPage?.strokes,twice)
        XCTAssertTrue(session.selectedStrokeIDs.isEmpty)
        canvas.undoManager?.redo(); XCTAssertEqual(session.currentPage?.strokes,once)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:200)]),to:canvas); c.canvasViewDrawingDidChange(canvas)
        let added=try XCTUnwrap(session.currentPage?.strokes)
        XCTAssertEqual(Array(added.prefix(4)),once); XCTAssertEqual(added.count,5)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:Array(canvas.drawing.strokes.prefix(4))),to:canvas); c.canvasViewDrawingDidChange(canvas)
        XCTAssertEqual(session.currentPage?.strokes,once)
        canvas.undoManager?.undo(); XCTAssertEqual(session.currentPage?.strokes,added)
        canvas.undoManager?.undo(); XCTAssertEqual(session.currentPage?.strokes,once)
        XCTAssertNil(session.operationError); await session.flush(); XCTAssertEqual(session.saveState,.saved)
    }
    func testCaptureFinalCanvasBeforeEachCommandRetainsSelectionAndNativeUndoBoundary() async throws {
        for duplicate in [false,true] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let store=DocumentStore(directory:root), session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
            let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
            let c=NoteCanvas.Coordinator(session:session,reference:reference); c.attach(to:canvas)
            c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke()]),to:canvas); c.canvasViewDrawingDidChange(canvas)
            let a=try XCTUnwrap(session.currentPage?.strokes); try selectionBox(session)
            // Final B of the SAME gesture includes more native ink; callback has not arrived yet.
            c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:200)]),to:canvas)
            if duplicate { reference.duplicateSelectedInk(in:session) } else { reference.deleteSelectedInk(in:session) }
            let commanded=try XCTUnwrap(session.currentPage?.strokes)
            XCTAssertEqual(commanded.count,duplicate ? 3 : 1); XCTAssertEqual(session.document?.revision,3)
            c.canvasViewDrawingDidChange(canvas) // delayed native delegate sees the current live canvas
            XCTAssertEqual(session.currentPage?.strokes,commanded)
            canvas.undoManager?.undo()
            let b=try XCTUnwrap(session.currentPage?.strokes)
            XCTAssertEqual(b.count,2); XCTAssertEqual(b[0],a[0]); XCTAssertTrue(session.selectedStrokeIDs.isEmpty)
            canvas.undoManager?.undo(); XCTAssertEqual(session.currentPage?.strokes,[]); XCTAssertFalse(canvas.undoManager?.canUndo ?? true)
            canvas.undoManager?.redo(); XCTAssertEqual(session.currentPage?.strokes,b)
            canvas.undoManager?.redo(); XCTAssertEqual(session.currentPage?.strokes,commanded)
            XCTAssertEqual(session.document?.revision,7); XCTAssertNil(session.operationError)
            await session.flush(); let disk=try await store.load(); XCTAssertEqual(disk?.document,session.document)
        }
    }
    func testEmptyAndFailedSelectionCommandsPreserveRedoAndSelectedValues() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let session=EditorSession(store:DocumentStore(directory:root),saveDelay:.seconds(60)); await session.loadIfNeeded()
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let c=NoteCanvas.Coordinator(session:session,reference:reference); c.attach(to:canvas)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke()]),to:canvas); c.canvasViewDrawingDidChange(canvas)
        try selectionBox(session); reference.duplicateSelectedInk(in:session)
        let expected=try XCTUnwrap(session.document); canvas.undoManager?.undo()
        let before=session.document
        XCTAssertTrue(canvas.undoManager?.canRedo ?? false)
        try c.inkUndo?.duplicateSelection(dx:20,dy:20); try c.inkUndo?.deleteSelection()
        XCTAssertEqual(session.document,before); XCTAssertTrue(canvas.undoManager?.canRedo ?? false)
        try selectionBox(session); let ids=session.selectedStrokeIDs
        XCTAssertThrowsError(try c.inkUndo?.duplicateSelection(dx:.nan,dy:20))
        XCTAssertEqual(session.document,before); XCTAssertEqual(session.selectedStrokeIDs,ids)
        XCTAssertTrue(canvas.undoManager?.canRedo ?? false)
        canvas.undoManager?.redo(); XCTAssertEqual(session.currentPage?.strokes,expected.pages[0].strokes)
        XCTAssertTrue(session.selectedStrokeIDs.isEmpty)
    }
    func testDeleteOfIdenticalSelectionDoesNotLeaveDeadIdentityCandidatesForNextInput() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let session=EditorSession(store:DocumentStore(directory:root),saveDelay:.seconds(60)); await session.loadIfNeeded()
        session.receiveDrawing(PKDrawing(strokes:[sampleStroke(),sampleStroke()]))
        try selectionBox(session); _=try session.deleteSelectedInk()
        session.receiveDrawing(PKDrawing(strokes:[sampleStroke()]))
        XCTAssertEqual(session.strokeCount,1); XCTAssertEqual(session.serializedVisibleInk?.count,1)
        XCTAssertNil(session.operationError); await session.flush(); XCTAssertEqual(session.saveState,.saved)
    }
    func testAmbiguousNativeEraseAfterCloneDeleteUndoKeepsVisibleInkAndBothSavedFiles() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=DocumentStore(directory:root), session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let c=NoteCanvas.Coordinator(session:session,reference:reference); c.attach(to:canvas)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke(),sampleStroke()]),to:canvas); c.canvasViewDrawingDidChange(canvas)
        try selectionBox(session); reference.duplicateSelectedInk(in:session); reference.deleteSelectedInk(in:session)
        canvas.undoManager?.undo(); await session.flush()
        let good=try XCTUnwrap(session.document), nativeGood=session.drawing
        let primary=try Data(contentsOf:root.appendingPathComponent("document.json")), backup=try Data(contentsOf:root.appendingPathComponent("document.backup.json"))
        c.canvasViewDidBeginUsingTool(canvas)
        let ambiguous=PKDrawing(strokes:Array(nativeGood.strokes.dropFirst()))
        c.apply(ambiguous,to:canvas); c.canvasViewDrawingDidChange(canvas)
        XCTAssertEqual(session.drawing,ambiguous); XCTAssertNil(session.serializedVisibleInk)
        XCTAssertEqual(session.document,good); XCTAssertFalse(session.canApplyInkCommand)
        await session.flush()
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("document.json")),primary)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("document.backup.json")),backup)
        canvas.undoManager?.undo(); XCTAssertEqual(session.document,good); XCTAssertEqual(session.drawing,nativeGood)
        XCTAssertEqual(session.saveState,.saved)
        canvas.undoManager?.redo(); XCTAssertEqual(session.drawing,ambiguous); XCTAssertNil(session.serializedVisibleInk)
        canvas.undoManager?.undo(); XCTAssertEqual(session.document,good); XCTAssertEqual(session.saveState,.saved)
    }
    func testCaptureBeforeQueuedDelegateRecordsFinalInkForUndoRedoAndSave() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=DocumentStore(directory:root), session=EditorSession(store:store,saveDelay:.seconds(60))
        await session.loadIfNeeded()
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:canvas)
        canvas.delegate=coordinator
        coordinator.canvasViewDidBeginUsingTool(canvas)
        coordinator.apply(PKDrawing(strokes:[sampleStroke()]),to:canvas)
        coordinator.canvasViewDrawingDidChange(canvas)
        var finalStroke=canvas.drawing.strokes[0]; finalStroke.transform.tx += 10
        coordinator.apply(PKDrawing(strokes:[finalStroke]),to:canvas)
        reference.captureDrawing(in:session) // Toolbar/background sees B before its delegate.
        await session.flush()
        let final=try XCTUnwrap(session.document), disk=try await store.load()
        XCTAssertEqual(disk?.document,final)
        coordinator.canvasViewDrawingDidChange(canvas) // Queued B callback must not create another step.
        canvas.undoManager?.undo()
        XCTAssertEqual(session.currentPage?.strokes,[]); XCTAssertNil(session.operationError)
        XCTAssertFalse(canvas.undoManager?.canUndo ?? true)
        canvas.undoManager?.redo()
        XCTAssertEqual(session.currentPage?.strokes,final.pages[0].strokes)
        await session.flush(); let restored=try await store.load()
        XCTAssertEqual(restored?.document,session.document)
        XCTAssertEqual(restored?.document.pages[0].strokes,final.pages[0].strokes)
    }
    func testNativeDelegateUpdatesCoalesceAndRedoUsesLatestCompleteDrawing() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let session=EditorSession(store:DocumentStore(directory:root),saveDelay:.seconds(60)); await session.loadIfNeeded()
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:canvas)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing=PKDrawing(strokes:[sampleStroke()]); coordinator.canvasViewDrawingDidChange(canvas)
        // Another callback for the same gesture can deliver final point values.
        canvas.drawing=PKDrawing(strokes:[sampleStroke(offset:10)]); coordinator.canvasViewDrawingDidChange(canvas)
        let finalFirst=try XCTUnwrap(session.currentPage?.strokes)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing=PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:80)])
        coordinator.canvasViewDrawingDidChange(canvas)
        let finalBoth=try XCTUnwrap(session.currentPage?.strokes)
        reference.undo(in:session); XCTAssertEqual(session.currentPage?.strokes,finalFirst)
        reference.undo(in:session); XCTAssertEqual(session.currentPage?.strokes,[])
        reference.redo(in:session); XCTAssertEqual(session.currentPage?.strokes,finalFirst)
        reference.redo(in:session); XCTAssertEqual(session.currentPage?.strokes,finalBoth)
        XCTAssertFalse(canvas.undoManager?.isUndoRegistrationEnabled ?? true)
        await session.flush(); XCTAssertEqual(session.saveState,.saved)
    }
    func testUnsupportedNativeInputCanBeUndoneWithoutOverwritingSavedInk() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=DocumentStore(directory:root), session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        let original=session.document, canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:canvas)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing=PKDrawing(strokes:[sampleStroke(ink:.pencil)]); coordinator.canvasViewDrawingDidChange(canvas)
        XCTAssertNil(session.serializedVisibleInk); XCTAssertEqual(session.strokeCount,1)
        reference.undo(in:session); XCTAssertEqual(session.strokeCount,0); XCTAssertEqual(session.document,original)
        XCTAssertEqual(session.saveState,.saved)
        reference.redo(in:session); XCTAssertEqual(session.strokeCount,1); XCTAssertNil(session.serializedVisibleInk)
        await session.flush(); let disk=try await store.load(); XCTAssertEqual(disk?.document,original)
        reference.undo(in:session); XCTAssertEqual(session.strokeCount,0); XCTAssertEqual(session.saveState,.saved)
    }
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
