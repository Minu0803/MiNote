import XCTest
import PencilKit
import PDFKit
@testable import MiNote
@testable import MiNoteCore

@MainActor final class SelectionSessionTests: XCTestCase {
    private func directory() throws -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }; return root
    }
    private func selectAll(_ session: EditorSession) throws {
        try session.selectInk(polygon:[.init(x:0,y:0),.init(x:1000,y:0),.init(x:1000,y:1000),.init(x:0,y:1000)])
    }
    private func fixture(in root: URL) async throws -> DocumentStore {
        var document=try fixtureDocument("multi-source"); document.lastOpenedPageID=document.pages[1].id
        try FileManager.default.createDirectory(at:root.appendingPathComponent("assets"),withIntermediateDirectories:true)
        let bytes=try Data(contentsOf:fixtureURL("source",extension:"pdf"))
        for asset in document.pdfAssets { try bytes.write(to:root.appendingPathComponent(asset.relativePath)) }
        let store=DocumentStore(directory:root); try await store.save(document); return store
    }
    func testMoveAutosavesAndEditableBackupRestoresAllMetadataAndPDFBytes() async throws {
        let root=try directory(), source=root.appendingPathComponent("source"), store=try await fixture(in:source)
        let registry=ExportFileRegistry(root:root.appendingPathComponent("exports"))
        let session=EditorSession(store:store,saveDelay:.milliseconds(15),exportRegistry:registry); await session.loadIfNeeded()
        let original=try XCTUnwrap(session.document), generation=session.canvasGeneration
        try selectAll(session); let moved=try XCTUnwrap(session.translateSelectedInk(dx:30,dy:-15))
        for _ in 0..<100 where session.saveState != .saved { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(session.saveState,.saved); XCTAssertEqual(session.canvasGeneration,generation)
        let expected=try XCTUnwrap(session.document), disk=try await store.load()
        XCTAssertEqual(disk?.document,expected); XCTAssertEqual(expected.revision,original.revision+1)
        XCTAssertEqual(expected.pages[1].strokes[0].id,original.pages[1].strokes[0].id)
        XCTAssertEqual(expected.pages[1].strokes[0].transform.tx,35); XCTAssertEqual(expected.pages[1].strokes[0].transform.ty,-9)
        XCTAssertEqual(expected.pages[0],original.pages[0]); XCTAssertEqual(expected.deletedPages,original.deletedPages)
        XCTAssertEqual(expected.pdfAssets,original.pdfAssets); XCTAssertEqual(moved.before,original.pages[1].strokes)
        let reopened=EditorSession(store:DocumentStore(directory:source)); await reopened.loadIfNeeded()
        XCTAssertEqual(reopened.document,expected); XCTAssertTrue(reopened.selectedStrokeIDs.isEmpty)
        let exported=await session.exportBackup(), file=try XCTUnwrap(exported), prepared=try await BackupFileAccess().prepare(url:file.url)
        defer { try? FileManager.default.removeItem(at:prepared.stagingDirectory) }
        XCTAssertEqual(prepared.document,expected)
        let library=LibrarySession(store:LibraryStore(directory:root.appendingPathComponent("library")),exportRegistry:registry)
        await library.load(); await library.createNote(title:"Keep",folderID:nil)
        let keepID=try XCTUnwrap(library.notes.first?.id)
        await library.restoreBackup(from:file.url,folderID:nil); await library.restoreBackup(from:file.url,folderID:nil)
        XCTAssertNil(library.operationError); XCTAssertEqual(library.notes.count,3)
        XCTAssertTrue(library.notes.contains { $0.id == keepID })
        let restoredID=try XCTUnwrap(library.notes.first(where:{$0.id != keepID && $0.id != expected.id})?.id)
        await library.openNote(restoredID)
        let restored=try XCTUnwrap(library.selectedEditor), doc=try XCTUnwrap(restored.document)
        XCTAssertEqual(doc.pages,expected.pages); XCTAssertEqual(doc.deletedPages,expected.deletedPages); XCTAssertEqual(doc.pdfAssets,expected.pdfAssets)
        XCTAssertEqual(doc.revision,expected.revision); XCTAssertEqual(doc.lastOpenedPageID,expected.lastOpenedPageID)
        XCTAssertTrue(restored.selectedStrokeIDs.isEmpty)
        let canvas=InkCanvasView(); XCTAssertFalse(canvas.undoManager?.canUndo ?? true)
        let bytes=try Data(contentsOf:fixtureURL("source",extension:"pdf"))
        for asset in doc.pdfAssets {
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("library/notes/\(restoredID.uuidString)/\(asset.relativePath)")),bytes)
            XCTAssertEqual(try Data(contentsOf:source.appendingPathComponent(asset.relativePath)),bytes)
        }
        try await registry.release(file.lease)
    }
    func testENOSPCPreservesVisibleMoveAndPrimaryBackupBlocksCommandsAndRetriesLatest() async throws {
        let root=try directory(), fault=SelectionWriteFault()
        let store=DocumentStore(directory:root,atomicWriter:{ data,url in
            if fault.fails(url) { throw POSIXError(.ENOSPC) }; try data.write(to:url,options:.atomic)
        })
        let registry=ExportFileRegistry(root:root.appendingPathComponent("exports"))
        let session=EditorSession(store:store,saveDelay:.seconds(60),exportRegistry:registry); await session.loadIfNeeded()
        session.receiveDrawing(PKDrawing(strokes:[sampleStroke()])); await session.flush()
        let primary=root.appendingPathComponent("document.json"), backup=root.appendingPathComponent("document.backup.json")
        let oldPrimary=try Data(contentsOf:primary), oldBackup=try Data(contentsOf:backup)
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas; canvas.drawing=session.drawing
        let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:canvas)
        try selectAll(session); fault.arm(); try coordinator.inkUndo?.move(dx:30,dy:-15)
        let expected=try XCTUnwrap(session.document), visible=session.drawing
        await session.flush(); guard case .failed = session.saveState else { return XCTFail("ENOSPC must fail") }
        XCTAssertEqual(session.drawing,visible); XCTAssertEqual(session.document,expected)
        XCTAssertEqual(try Data(contentsOf:primary),oldPrimary); XCTAssertEqual(try Data(contentsOf:backup),oldBackup)
        XCTAssertThrowsError(try session.translateSelectedInk(dx:10,dy:10))
        reference.undo(in:session); XCTAssertEqual(session.document,expected); XCTAssertTrue(canvas.undoManager?.canUndo ?? false)
        let failedBackup=await session.exportBackup(); XCTAssertNil(failedBackup)
        fault.disarm(); session.retrySave(); await session.flush(); XCTAssertEqual(session.saveState,.saved)
        let disk=try await store.load(); XCTAssertEqual(disk?.document,expected)
        let exported=await session.exportBackup(), file=try XCTUnwrap(exported), prepared=try await BackupFileAccess().prepare(url:file.url)
        defer { try? FileManager.default.removeItem(at:prepared.stagingDirectory) }
        XCTAssertEqual(prepared.document,expected); try await registry.release(file.lease)
    }
    func testUnsupportedOrAmbiguousInputAfterMoveKeepsDiskAndRejectsSelectionCommands() async throws {
        for unsupported in [true,false] {
            let root=try directory(), store=DocumentStore(directory:root)
            let native=PKDrawing(strokes:unsupported ? [sampleStroke()] : [sampleStroke(),sampleStroke()])
            let document=NoteDocument(title:"Safe",pages:[NotePage(strokes:try InkAdapter.encode(native,preserving:[]))])
            try await store.save(document)
            let session=EditorSession(store:store,saveDelay:.seconds(60),exportRegistry:ExportFileRegistry(root:root.appendingPathComponent("exports")))
            await session.loadIfNeeded(); try selectAll(session); _=try session.translateSelectedInk(dx:30,dy:-15); await session.flush()
            let good=try XCTUnwrap(session.document), nativeGood=session.drawing
            let primary=try Data(contentsOf:root.appendingPathComponent("document.json")), backup=try Data(contentsOf:root.appendingPathComponent("document.backup.json"))
            let bad=unsupported ? PKDrawing(strokes:[sampleStroke(ink:.pencil)]) : PKDrawing(strokes:[nativeGood.strokes[0]])
            session.receiveDrawing(bad)
            XCTAssertEqual(session.drawing,bad); XCTAssertEqual(session.document,good); XCTAssertFalse(session.canApplyInkCommand)
            XCTAssertThrowsError(try selectAll(session)); XCTAssertThrowsError(try session.translateSelectedInk(dx:1,dy:1))
            let file=await session.exportBackup(); XCTAssertNil(file); await session.flush()
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("document.json")),primary)
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("document.backup.json")),backup)
            session.receiveDrawing(nativeGood); session.retrySave(); await session.flush()
            XCTAssertEqual(session.saveState,.saved); XCTAssertEqual(session.document,good)
        }
    }
    func testBusyBackupLateInputAndPreviousGenerationCannotMoveOrOverwriteOtherPage() async throws {
        let root=try directory(), store=try await fixture(in:root.appendingPathComponent("source")), gate=SelectionBlockingGate()
        let service=NoteBackup(chunkWriter:{ handle,data in try handle.write(contentsOf:data); gate.blockOnce() })
        let session=EditorSession(store:store,saveDelay:.seconds(60),exportRegistry:ExportFileRegistry(root:root.appendingPathComponent("exports")),backupService:service)
        await session.loadIfNeeded()
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas; canvas.drawing=session.drawing
        let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:canvas)
        try selectAll(session); try coordinator.inkUndo?.move(dx:30,dy:-15); await session.flush()
        let before=try XCTUnwrap(session.document)
        let job=Task { await session.exportBackup() }, entered=await Task.detached { gate.waitForEntry() }.value
        XCTAssertTrue(entered); XCTAssertTrue(session.isProcessing)
        XCTAssertThrowsError(try session.translateSelectedInk(dx:10,dy:10)); reference.undo(in:session)
        XCTAssertEqual(session.document,before); XCTAssertTrue(canvas.undoManager?.canUndo ?? false)
        coordinator.canvasViewDidBeginUsingTool(canvas)
        canvas.drawing=PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:70)])
        coordinator.canvasViewDrawingDidChange(canvas)
        XCTAssertEqual(session.currentPage?.strokes.first,before.pages[1].strokes[0]); XCTAssertEqual(session.strokeCount,2)
        gate.released.signal(); let output=await job.value
        XCTAssertNil(output); XCTAssertNotNil(session.operationError); await session.flush()
        let latest=try XCTUnwrap(session.document), disk=try await store.load(); XCTAssertEqual(disk?.document,latest)
        XCTAssertEqual(latest.revision,before.revision+1)
        await session.selectPage(0); let other=try XCTUnwrap(session.document)
        XCTAssertTrue(session.selectedStrokeIDs.isEmpty); XCTAssertNotEqual(session.canvasGeneration,coordinator.generation)
        canvas.drawing=PKDrawing(strokes:[sampleStroke(offset:300)]); coordinator.canvasViewDrawingDidChange(canvas)
        canvas.undoManager?.undo(); XCTAssertEqual(session.document,other)
        let current=try await store.load(); XCTAssertEqual(current?.document,other)
    }
    func testMovedInkPDFPixelsStayInDocumentCoordinatesForAllCropRotations() async throws {
        let root=try directory(), bytes=try PDFFixture.data(), source=root.appendingPathComponent("source.pdf")
        try bytes.write(to:source)
        let prepared=try await PDFImporter().prepare(data:bytes,filename:"source.pdf")
        let noteRoot=root.appendingPathComponent("note"), store=DocumentStore(directory:noteRoot)
        try FileManager.default.createDirectory(at:noteRoot.appendingPathComponent("assets"),withIntermediateDirectories:true)
        try bytes.write(to:noteRoot.appendingPathComponent(prepared.asset.relativePath))
        var doc=NoteDocument(title:"Pixels",pages:prepared.pages,pdfAssets:[prepared.asset])
        for i in doc.pages.indices { doc.pages[i].strokes=[testInk()] }
        try await store.save(doc)
        let session=EditorSession(store:store,saveDelay:.seconds(60),exportRegistry:ExportFileRegistry(root:root.appendingPathComponent("exports")))
        await session.loadIfNeeded()
        for i in 0..<4 {
            await session.selectPage(i); try selectAll(session)
            let host=PageZoomHost(frame:CGRect(x:0,y:0,width:834,height:900)), page=try XCTUnwrap(session.currentPage)
            host.configurePage(size:CGSize(width:page.width,height:page.height),pdfPage:session.currentPDFPage); host.layoutIfNeeded()
            let scroll=try XCTUnwrap(host.subviews.first as? UIScrollView)
            for zoom in [1.0,2.0,5.0] {
                scroll.zoomScale=scroll.minimumZoomScale*zoom
                let a=host.lasso.convert(host.convert(CGPoint(x:130,y:120),from:host.canvas),from:host)
                let b=host.lasso.convert(host.convert(CGPoint(x:160,y:105),from:host.canvas),from:host)
                XCTAssertEqual(b.x-a.x,30,accuracy:0.0001); XCTAssertEqual(b.y-a.y,-15,accuracy:0.0001)
            }
            _=try session.translateSelectedInk(dx:30,dy:-15)
        }
        let exported=await session.exportPDF(), file=try XCTUnwrap(exported), pdf=try XCTUnwrap(PDFDocument(url:file.url))
        for i in 0..<4 {
            let page=try XCTUnwrap(pdf.page(at:i)), image=renderPDFPage(page,size:try PDFGeometry(page:page).size)
            let moved=pixel(image,at:CGPoint(x:160,y:105)), old=pixel(image,at:CGPoint(x:130,y:120)), outline=pixel(image,at:CGPoint(x:150,y:77))
            XCTAssertGreaterThan(moved[2],150); XCTAssertLessThan(moved[0],100)
            XCTAssertLessThan(Int(old[2])-Int(old[0]),25,"No blue ink at old position, rotation \(i*90)")
            XCTAssertEqual(outline[0],outline[2],"Selection outline must not be exported")
        }
        XCTAssertEqual(try Data(contentsOf:source),bytes); XCTAssertEqual(try Data(contentsOf:noteRoot.appendingPathComponent(prepared.asset.relativePath)),bytes)
        try await session.exportRegistry.release(file.lease)
    }
    func testGenerateActualLassoMovedV3Fixture() async throws {
        let root=try directory(), store=try await fixture(in:root)
        let session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        let before=try XCTUnwrap(session.document); try selectAll(session); _=try session.translateSelectedInk(dx:30,dy:-15)
        let moved=try XCTUnwrap(session.document)
        let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("PortableInkGenerated")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try DocumentCodec.encode(before).write(to:output.appendingPathComponent("lasso-source.json"),options:.atomic)
        try DocumentCodec.encode(moved).write(to:output.appendingPathComponent("lasso-moved.json"),options:.atomic)
        XCTAssertEqual(moved.revision,before.revision+1); XCTAssertEqual(moved.pages[1].strokes[0].transform.tx,35)
    }
}
private final class SelectionWriteFault: @unchecked Sendable {
    private let lock=NSLock(); private var armed=false
    func arm() { lock.lock(); defer { lock.unlock() }; armed=true }
    func disarm() { lock.lock(); defer { lock.unlock() }; armed=false }
    func fails(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return armed && url.lastPathComponent=="document.backup.json" }
}
private final class SelectionBlockingGate: @unchecked Sendable {
    let entered=DispatchSemaphore(value:0), released=DispatchSemaphore(value:0)
    private let lock=NSLock(); private var used=false
    func waitForEntry() -> Bool { entered.wait(timeout:.now()+5) == .success }
    func blockOnce() { lock.lock(); let block = !used; used=true; lock.unlock(); if block { entered.signal(); _=released.wait(timeout:.now()+8) } }
}
