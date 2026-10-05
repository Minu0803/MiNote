import XCTest
import PencilKit
@testable import MiNoteCore
@testable import MiNote

@MainActor final class InkClipboardTests: XCTestCase {
    private func root() -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }; return url
    }
    private func selectAll(_ s:EditorSession) throws {
        try s.selectInk(polygon:[.init(x:-1000,y:-1000),.init(x:2000,y:-1000),.init(x:2000,y:2000),.init(x:-1000,y:2000)])
    }
    private func setup() async throws -> (EditorSession,InkCanvasView,CanvasReference,NoteCanvas.Coordinator) {
        let s=EditorSession(store:DocumentStore(directory:root()),saveDelay:.seconds(60)); await s.loadIfNeeded()
        let canvas=InkCanvasView(), ref=CanvasReference(); ref.canvas=canvas
        let c=NoteCanvas.Coordinator(session:s,reference:ref); c.attach(to:canvas)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke()]),to:canvas); c.capture(canvas)
        return (s,canvas,ref,c)
    }
    private func provider(_ data:Data) -> NSItemProvider {
        let p=NSItemProvider(); p.registerDataRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,visibility:.all) { done in done(data,nil); return nil }; return p
    }
    func testCopyKeepsClipboardForEmptyOrFailedEncodingAndDoesNotEditHistory() async throws {
        let (s,canvas,ref,c)=try await setup(); _=c
        let board=try XCTUnwrap(UIPasteboard(name:.init(UUID().uuidString),create:true))
        defer { UIPasteboard.remove(withName:board.name) }
        board.string="keep"; let access=InkClipboardAccess(pasteboard:board)
        ref.copySelectedInk(in:s,access:access); XCTAssertEqual(board.string,"keep")
        try selectAll(s); let before=s.document
        ref.copySelectedInk(in:s,access:access)
        let data=try XCTUnwrap(board.data(forPasteboardType:InkClipboardAccess.typeIdentifier))
        XCTAssertEqual(try InkClipboardCodec.decode(data).strokes,s.currentPage?.strokes)
        XCTAssertEqual(s.document,before); XCTAssertTrue(canvas.undoManager?.canUndo ?? false)
        XCTAssertThrowsError(try access.write(Data("{broken".utf8)))
        XCTAssertEqual(board.data(forPasteboardType:InkClipboardAccess.typeIdentifier),data)
        canvas.undoManager?.undo(); XCTAssertTrue(s.currentPage?.strokes.isEmpty == true)
    }
    func testPasteUsesFreshIDsAndOneNativeHistoryWithFinalCapture() async throws {
        let (s,canvas,ref,c)=try await setup(); try selectAll(s)
        let payload=try InkClipboardCodec.decode(XCTUnwrap(s.copySelectedInk()))
        // B arrives before its delegate: paste start must ingest B and retain its native boundary.
        c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:200)]),to:canvas)
        await ref.pasteInk(from:[provider(try InkClipboardCodec.encode(payload))],in:s,viewportCenter:CGPoint(x:300,y:400))
        let pasted=try XCTUnwrap(s.currentPage?.strokes); XCTAssertEqual(pasted.count,3)
        XCTAssertEqual(Set(pasted.map(\.id)).count,3); XCTAssertEqual(s.selectedStrokeIDs,[pasted[2].id])
        // Source center(35,26) -> viewport center(300,400), tx5+265, ty6+374.
        XCTAssertEqual(pasted[2].transform.tx,270); XCTAssertEqual(pasted[2].transform.ty,380)
        c.capture(canvas); canvas.undoManager?.undo(); XCTAssertEqual(s.currentPage?.strokes,Array(pasted.prefix(2)))
        canvas.undoManager?.undo(); XCTAssertTrue(s.currentPage?.strokes.isEmpty == true)
        canvas.undoManager?.redo(); XCTAssertEqual(s.currentPage?.strokes,Array(pasted.prefix(2)))
        canvas.undoManager?.redo(); XCTAssertEqual(s.currentPage?.strokes,pasted)
        XCTAssertTrue(s.selectedStrokeIDs.isEmpty); XCTAssertNil(s.operationError)
    }
    func testPenPastePenUndoThreeAndRedoThreeKeepsExactIDs() async throws {
        let (s,canvas,ref,c)=try await setup(); try selectAll(s)
        let original=try XCTUnwrap(s.currentPage?.strokes), data=try XCTUnwrap(s.copySelectedInk())
        await ref.pasteInk(from:[provider(data)],in:s,viewportCenter:.init(x:300,y:400))
        let pasted=try XCTUnwrap(s.currentPage?.strokes)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:200)]),to:canvas); c.capture(canvas)
        let full=try XCTUnwrap(s.currentPage?.strokes)
        for want in [pasted,original,[]] { canvas.undoManager?.undo(); XCTAssertEqual(s.currentPage?.strokes,want) }
        for want in [original,pasted,full] { canvas.undoManager?.redo(); XCTAssertEqual(s.currentPage?.strokes,want) }
        XCTAssertTrue(s.selectedStrokeIDs.isEmpty); XCTAssertNil(s.operationError)
        await s.flush(); XCTAssertEqual(s.saveState,.saved)
    }
    func testOverlappingPasteAmbiguousNativeEraseKeepsDiskAndOwnedUndoRecovers() async throws {
        let dir=root(), store=DocumentStore(directory:dir), s=EditorSession(store:store,saveDelay:.seconds(60)); await s.loadIfNeeded()
        let canvas=InkCanvasView(), ref=CanvasReference(); ref.canvas=canvas
        let c=NoteCanvas.Coordinator(session:s,reference:ref); c.attach(to:canvas)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke()]),to:canvas); c.capture(canvas); try selectAll(s)
        let data=try XCTUnwrap(s.copySelectedInk())
        await ref.pasteInk(from:[provider(data)],in:s,viewportCenter:.init(x:35,y:26))
        let both=try XCTUnwrap(s.currentPage?.strokes); await s.flush()
        let primary=try Data(contentsOf:dir.appendingPathComponent("document.json"))
        let backup=try Data(contentsOf:dir.appendingPathComponent("document.backup.json"))
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[canvas.drawing.strokes[0]]),to:canvas); c.capture(canvas)
        XCTAssertEqual(s.currentPage?.strokes,both); XCTAssertEqual(s.drawing.strokes.count,1)
        if case .failed = s.saveState {} else { XCTFail("Ambiguous UUID must stop saving") }
        await s.flush(); XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("document.json")),primary)
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("document.backup.json")),backup)
        canvas.undoManager?.undo(); XCTAssertEqual(s.currentPage?.strokes,both); XCTAssertEqual(s.drawing.strokes.count,2)
        await s.flush(); XCTAssertEqual(s.saveState,.saved)
        canvas.undoManager?.undo(); XCTAssertEqual(s.currentPage?.strokes.count,1)
        canvas.undoManager?.redo(); XCTAssertEqual(s.currentPage?.strokes,both)
    }
    func testDelayedProviderRejectsNewInputPageGenerationAndOtherSession() async throws {
        for change in 0..<4 {
            let (s,canvas,ref,c)=try await setup(); try selectAll(s)
            let bytes=try XCTUnwrap(s.copySelectedInk()), gate=ClipboardProviderGate(), p=NSItemProvider()
            p.registerDataRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,visibility:.all) { done in gate.install(done); return nil }
            let request=Task { await ref.pasteInk(from:[p],in:s,viewportCenter:.init(x:300,y:400)) }
            for _ in 0..<100 where !gate.ready { try await Task.sleep(for:.milliseconds(10)) }
            XCTAssertTrue(gate.ready)
            if change==0 { c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:200)]),to:canvas); c.capture(canvas) }
            if change==1 { await s.applyPageCommand(.insert(after:try XCTUnwrap(s.currentPage?.id),paper:.blank)) }
            if change==2 { await s.selectPage(0) } // Same page does not change generation, so force a real reload.
            if change==2 { await s.applyPageCommand(.insert(after:try XCTUnwrap(s.currentPage?.id),paper:.grid)); await s.selectPage(0) }
            if change==3 {
                let other=EditorSession(store:DocumentStore(directory:root())); await other.loadIfNeeded()
                let otherCanvas=InkCanvasView(); ref.canvas=otherCanvas
                let otherC=NoteCanvas.Coordinator(session:other,reference:ref); otherC.attach(to:otherCanvas)
                gate.complete(bytes); await request.value
                XCTAssertTrue(other.currentPage?.strokes.isEmpty == true); continue
            }
            let before=s.document, visible=s.drawing, redo=canvas.undoManager?.canRedo
            gate.complete(bytes); await request.value
            XCTAssertEqual(s.document,before); XCTAssertEqual(s.drawing,visible)
            XCTAssertEqual(canvas.undoManager?.canRedo,redo); XCTAssertNotNil(s.operationError)
        }
    }
    func testProviderMalformedMultipleAndCancelledRequestsPreserveCurrentDrawingAndStacks() async throws {
        let (s,canvas,ref,c)=try await setup(); _=c
        let before=s.document, native=s.drawing
        for providers in [[NSItemProvider()], [provider(Data("bad".utf8))], [provider(Data()),provider(Data())]] {
            await ref.pasteInk(from:providers,in:s,viewportCenter:.init(x:300,y:400))
            XCTAssertEqual(s.document,before); XCTAssertEqual(s.drawing,native)
            XCTAssertTrue(canvas.undoManager?.canUndo ?? false)
        }
        let gate=ClipboardProviderGate(), p=NSItemProvider()
        p.registerDataRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,visibility:.all) { done in gate.install(done); return Progress(totalUnitCount:1) }
        let task=Task { try await InkClipboardAccess().read(from:[p]) }
        for _ in 0..<100 where !gate.ready { try await Task.sleep(for:.milliseconds(10)) }
        task.cancel()
        do { _=try await task.value; XCTFail("cancel must throw") } catch { XCTAssertTrue(error is CancellationError) }
        gate.complete(Data("late".utf8))
        XCTAssertEqual(s.document,before)
    }
    func testDelayedProviderRejectsUnreportedFinalCanvasAndNativeUndoKeepsNewInput() async throws {
        let (s,canvas,ref,c)=try await setup(); try selectAll(s)
        let data=try XCTUnwrap(s.copySelectedInk()), original=s.currentPage?.strokes, gate=ClipboardProviderGate(), p=NSItemProvider()
        p.registerDataRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,visibility:.all) { done in gate.install(done); return nil }
        let request=Task { await ref.pasteInk(from:[p],in:s,viewportCenter:.init(x:300,y:400)) }
        for _ in 0..<100 where !gate.ready { try await Task.sleep(for:.milliseconds(10)) }
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:200)]),to:canvas)
        gate.complete(data); await request.value
        let latest=try XCTUnwrap(s.currentPage?.strokes); XCTAssertEqual(latest.count,2); XCTAssertNotNil(s.operationError)
        c.capture(canvas); canvas.undoManager?.undo(); XCTAssertEqual(s.currentPage?.strokes,original)
        canvas.undoManager?.redo(); XCTAssertEqual(s.currentPage?.strokes,latest)
    }
    func testProviderCompletionWhileActualBackupWriterIsBusyCannotPasteOrConsumeStacks() async throws {
        let dir=root(), backupGate=ClipboardBackupGate()
        let service=NoteBackup(chunkWriter:{ handle,data in try handle.write(contentsOf:data); backupGate.block() })
        let s=EditorSession(store:DocumentStore(directory:dir),saveDelay:.seconds(60),exportRegistry:ExportFileRegistry(root:dir.appendingPathComponent("exports")),backupService:service); await s.loadIfNeeded()
        let canvas=InkCanvasView(), ref=CanvasReference(); ref.canvas=canvas
        let c=NoteCanvas.Coordinator(session:s,reference:ref); c.attach(to:canvas)
        c.canvasViewDidBeginUsingTool(canvas); c.apply(PKDrawing(strokes:[sampleStroke()]),to:canvas); c.capture(canvas); try selectAll(s)
        let bytes=try XCTUnwrap(s.copySelectedInk()), gate=ClipboardProviderGate(), p=NSItemProvider()
        p.registerDataRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,visibility:.all) { done in gate.install(done); return nil }
        let request=Task { await ref.pasteInk(from:[p],in:s,viewportCenter:.init(x:300,y:400)) }
        for _ in 0..<100 where !gate.ready { try await Task.sleep(for:.milliseconds(10)) }
        let backup=Task { await s.exportBackup() }, entered=await Task.detached { backupGate.waitForEntry() }.value
        XCTAssertTrue(entered); XCTAssertTrue(s.isProcessing)
        let before=s.document, drawing=s.drawing, undo=canvas.undoManager?.canUndo, redo=canvas.undoManager?.canRedo
        let primary=try Data(contentsOf:dir.appendingPathComponent("document.json")), recovery=try Data(contentsOf:dir.appendingPathComponent("document.backup.json"))
        gate.complete(bytes); await request.value; canvas.undoManager?.undo(); canvas.undoManager?.redo()
        XCTAssertEqual(s.document,before); XCTAssertEqual(s.drawing,drawing)
        XCTAssertEqual(canvas.undoManager?.canUndo,undo); XCTAssertEqual(canvas.undoManager?.canRedo,redo)
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("document.json")),primary)
        XCTAssertEqual(try Data(contentsOf:dir.appendingPathComponent("document.backup.json")),recovery)
        backupGate.released.signal(); let file=await backup.value; if let file { try await s.exportRegistry.release(file.lease) }
        canvas.undoManager?.undo(); XCTAssertTrue(s.currentPage?.strokes.isEmpty == true)
        canvas.undoManager?.redo(); XCTAssertEqual(s.document?.pages,before?.pages)
    }
    func testFileProviderAndOversizedOrFailedProviderReadAreBounded() async throws {
        let data=try InkClipboardCodec.encode(InkClipboardPayload(strokes:InkAdapter.encode(PKDrawing(strokes:[sampleStroke()]),preserving:[])))
        let url=root().appendingPathExtension("json"); try data.write(to:url); defer { try? FileManager.default.removeItem(at:url) }
        let p=NSItemProvider(); p.registerFileRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,fileOptions:[],visibility:.all) { done in done(url,false,nil); return nil }
        let actual=try await InkClipboardAccess().read(from:[p]); XCTAssertEqual(actual,data)
        let large=provider(Data(repeating:32,count:8*1024*1024+1))
        do { _=try await InkClipboardAccess().read(from:[large]); XCTFail("oversized") } catch {}
        let failed=NSItemProvider(); failed.registerDataRepresentation(forTypeIdentifier:InkClipboardAccess.typeIdentifier,visibility:.all) { done in done(nil,NSError(domain:"Read",code:1)); return nil }
        do { _=try await InkClipboardAccess().read(from:[failed]); XCTFail("provider failure") } catch {}
    }
}
private final class ClipboardProviderGate: @unchecked Sendable {
    private let lock=NSLock()
    private var callback: ((Data?,Error?)->Void)?
    var ready:Bool { lock.withLock { callback != nil } }
    func install(_ callback:@escaping (Data?,Error?)->Void) { lock.withLock { self.callback=callback } }
    func complete(_ data:Data) { let action=lock.withLock { let c=callback; callback=nil; return c }; action?(data,nil) }
}

private final class ClipboardBackupGate: @unchecked Sendable {
    let entered=DispatchSemaphore(value:0), released=DispatchSemaphore(value:0)
    private let lock=NSLock(); private var used=false
    func waitForEntry() -> Bool { entered.wait(timeout:.now()+5) == .success }
    func block() { let first=lock.withLock { if used { return false }; used=true; return true }; if first { entered.signal(); _=released.wait(timeout:.now()+8) } }
}
