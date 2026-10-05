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
    private func selectOriginalPDFInk(_ session: EditorSession) throws {
        try session.selectInk(polygon:[.init(x:80,y:100),.init(x:90,y:100),.init(x:90,y:110),.init(x:80,y:110)])
        XCTAssertEqual(session.selectedStrokeIDs.count,1)
    }
    func testSelectionAutosaveAndBackupRestoreKeepAllIdentitiesMetadataAndAssetBytes() async throws {
        let root=try directory(), store=try await fixture(in:root.appendingPathComponent("source"))
        let registry=ExportFileRegistry(root:root.appendingPathComponent("exports"))
        let session=EditorSession(store:store,saveDelay:.milliseconds(15),exportRegistry:registry); await session.loadIfNeeded()
        let before=try XCTUnwrap(session.document)
        try selectAll(session); _=try session.duplicateSelectedInk(dx:20,dy:20)
        let clone=try XCTUnwrap(session.currentPage?.strokes.last)
        try selectOriginalPDFInk(session); _=try session.deleteSelectedInk()
        let expected=try XCTUnwrap(session.document)
        XCTAssertEqual(expected.pages[1].strokes,[clone]); XCTAssertEqual(expected.revision,before.revision+2)
        XCTAssertEqual(expected.pages[0],before.pages[0]); XCTAssertEqual(expected.pages.dropFirst(2),before.pages.dropFirst(2))
        XCTAssertEqual(expected.deletedPages,before.deletedPages); XCTAssertEqual(expected.pdfAssets,before.pdfAssets)
        for _ in 0..<100 where session.saveState != .saved { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(session.saveState,.saved)
        let disk=try await store.load(); XCTAssertEqual(disk?.document,expected)
        let reopened=EditorSession(store:store); await reopened.loadIfNeeded()
        XCTAssertEqual(reopened.document,expected); XCTAssertTrue(reopened.selectedStrokeIDs.isEmpty)
        let exported=await session.exportBackup(), file=try XCTUnwrap(exported)
        let library=LibrarySession(store:LibraryStore(directory:root.appendingPathComponent("library")),exportRegistry:registry)
        await library.load(); await library.restoreBackup(from:file.url,folderID:nil)
        let id=try XCTUnwrap(library.notes.first?.id); XCTAssertEqual(id,expected.id) // Empty library preserves document identity; collisions allocate a fresh ID.
        await library.openNote(id); let restored=try XCTUnwrap(library.selectedEditor), document=try XCTUnwrap(restored.document)
        XCTAssertEqual(document.pages,expected.pages); XCTAssertEqual(document.deletedPages,expected.deletedPages)
        XCTAssertEqual(document.pdfAssets,expected.pdfAssets); XCTAssertEqual(document.revision,expected.revision)
        XCTAssertTrue(restored.selectedStrokeIDs.isEmpty)
        let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas
        let coordinator=NoteCanvas.Coordinator(session:restored,reference:reference); coordinator.attach(to:canvas)
        XCTAssertFalse(canvas.undoManager?.canUndo ?? true); XCTAssertFalse(canvas.undoManager?.canRedo ?? true)
        let bytes=try Data(contentsOf:fixtureURL("source",extension:"pdf"))
        for asset in document.pdfAssets {
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("library/notes/\(id.uuidString)/\(asset.relativePath)")),bytes)
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("source/\(asset.relativePath)")),bytes)
        }
        try await registry.release(file.lease)
    }
    func testSelectionENOSPCBlocksSystemUndoAndRedoWithoutConsumingEitherStack() async throws {
        for duplicate in [false,true] { for redo in [false,true] {
            let root=try directory(), fault=SelectionWriteFault()
            let store=DocumentStore(directory:root,atomicWriter:{ data,url in
                if fault.fails(url) { throw POSIXError(.ENOSPC) }; try data.write(to:url,options:.atomic)
            })
            let session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
            session.receiveDrawing(PKDrawing(strokes:[sampleStroke()])); await session.flush()
            let original=try XCTUnwrap(session.currentPage?.strokes)
            let primary=try Data(contentsOf:root.appendingPathComponent("document.json")), backup=try Data(contentsOf:root.appendingPathComponent("document.backup.json"))
            let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas; canvas.drawing=session.drawing
            let c=NoteCanvas.Coordinator(session:session,reference:reference); c.attach(to:canvas)
            try selectAll(session)
            if duplicate { reference.duplicateSelectedInk(in:session) } else { reference.deleteSelectedInk(in:session) }
            let edited=try XCTUnwrap(session.currentPage?.strokes)
            if redo { canvas.undoManager?.undo() }
            let before=try XCTUnwrap(session.document), native=session.drawing, ids=session.selectedStrokeIDs
            let canUndo=canvas.undoManager?.canUndo, canRedo=canvas.undoManager?.canRedo
            fault.arm(); await session.flush()
            guard case .failed = session.saveState else { return XCTFail("ENOSPC required") }
            XCTAssertThrowsError(try c.inkUndo?.deleteSelection()); XCTAssertThrowsError(try c.inkUndo?.duplicateSelection(dx:20,dy:20))
            canvas.undoManager?.undo(); canvas.undoManager?.redo()
            XCTAssertEqual(session.document,before); XCTAssertEqual(session.drawing,native); XCTAssertEqual(session.selectedStrokeIDs,ids)
            XCTAssertEqual(canvas.undoManager?.canUndo,canUndo); XCTAssertEqual(canvas.undoManager?.canRedo,canRedo)
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("document.json")),primary)
            XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("document.backup.json")),backup)
            fault.disarm(); session.retrySave(); await session.flush(); XCTAssertEqual(session.saveState,.saved)
            let recovered=try await store.load(); XCTAssertEqual(recovered?.document,before)
            if redo { canvas.undoManager?.redo() } else { canvas.undoManager?.undo() }
            XCTAssertEqual(session.currentPage?.strokes,redo ? edited : original)
            XCTAssertEqual(session.document?.revision,before.revision+1); XCTAssertNil(session.operationError)
            await session.flush(); let replayed=try await store.load(); XCTAssertEqual(replayed?.document,session.document)
        } }
    }
    func testSelectionBusyBackupRetainsStacksLateInputAndRejectsOldGenerationCommands() async throws {
        for redo in [false,true] {
            let root=try directory(), store=try await fixture(in:root.appendingPathComponent("source")), gate=SelectionBlockingGate()
            let service=NoteBackup(chunkWriter:{ handle,data in try handle.write(contentsOf:data); gate.blockOnce() })
            let session=EditorSession(store:store,saveDelay:.seconds(60),exportRegistry:ExportFileRegistry(root:root.appendingPathComponent("exports")),backupService:service)
            await session.loadIfNeeded()
            let canvas=InkCanvasView(), reference=CanvasReference(); reference.canvas=canvas; canvas.drawing=session.drawing
            let c=NoteCanvas.Coordinator(session:session,reference:reference); c.attach(to:canvas)
            try selectAll(session); reference.duplicateSelectedInk(in:session)
            let edited=try XCTUnwrap(session.currentPage?.strokes)
            if redo { canvas.undoManager?.undo() }
            await session.flush(); let before=try XCTUnwrap(session.document)
            let canUndo=canvas.undoManager?.canUndo, canRedo=canvas.undoManager?.canRedo
            let job=Task { await session.exportBackup() }, entered=await Task.detached { gate.waitForEntry() }.value
            XCTAssertTrue(entered); XCTAssertTrue(session.isProcessing)
            XCTAssertThrowsError(try c.inkUndo?.deleteSelection()); XCTAssertThrowsError(try c.inkUndo?.duplicateSelection(dx:20,dy:20))
            canvas.undoManager?.undo(); canvas.undoManager?.redo()
            XCTAssertEqual(session.document,before); XCTAssertEqual(canvas.undoManager?.canUndo,canUndo); XCTAssertEqual(canvas.undoManager?.canRedo,canRedo)
            if !redo {
                c.canvasViewDidBeginUsingTool(canvas)
                c.apply(PKDrawing(strokes:canvas.drawing.strokes+[sampleStroke(offset:240)]),to:canvas)
                reference.captureDrawing(in:session) // Final native input before its queued delegate.
                c.canvasViewDrawingDidChange(canvas)
                XCTAssertEqual(session.strokeCount,3); XCTAssertEqual(Array(session.currentPage!.strokes.prefix(2)),edited)
            }
            gate.released.signal(); let file=await job.value
            if redo { let output=try XCTUnwrap(file); try await session.exportRegistry.release(output.lease); canvas.undoManager?.redo(); XCTAssertEqual(session.currentPage?.strokes,edited) }
            else { XCTAssertNil(file); XCTAssertNotNil(session.operationError); canvas.undoManager?.undo(); XCTAssertEqual(session.currentPage?.strokes,edited) }
            await session.flush(); let latest=try await store.load(); XCTAssertEqual(latest?.document,session.document)
            await session.selectPage(0); let current=session.document
            XCTAssertThrowsError(try c.inkUndo?.deleteSelection()); XCTAssertThrowsError(try c.inkUndo?.duplicateSelection(dx:20,dy:20))
            reference.deleteSelectedInk(in:session); reference.duplicateSelectedInk(in:session)
            c.apply(PKDrawing(strokes:[sampleStroke(offset:400)]),to:canvas); c.canvasViewDrawingDidChange(canvas)
            canvas.undoManager?.undo(); canvas.undoManager?.redo()
            XCTAssertEqual(session.document,current)
        }
    }
    private func assertScreenInk(_ host: PageZoomHost, original: Bool, phase: String) async throws {
        let previous=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window=UIWindow(frame:host.bounds); window.rootViewController=UIViewController()
        window.rootViewController?.view.addSubview(host); window.makeKeyAndVisible()
        defer { host.removeFromSuperview(); window.isHidden=true; previous?.makeKeyAndVisible() }
        host.layoutIfNeeded()
        let scroll=try XCTUnwrap(host.subviews.first as? UIScrollView)
        // Keep both expected positions visible at every production zoom scale.
        scroll.setContentOffset(CGPoint(x:max(-scroll.contentInset.left,140*scroll.zoomScale-scroll.bounds.width/2),
            y:max(-scroll.contentInset.top,130*scroll.zoomScale-scroll.bounds.height/2)),animated:false)
        try await Task.sleep(for:.milliseconds(200))
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        let image=UIGraphicsImageRenderer(size:host.bounds.size,format:format).image { _ in
            XCTAssertTrue(host.drawHierarchy(in:host.bounds,afterScreenUpdates:true))
        }
        let attachment=XCTAttachment(image:image); attachment.name=phase; attachment.lifetime = .keepAlways; add(attachment)
        for (point,present) in [(CGPoint(x:130,y:120),original),(CGPoint(x:150,y:140),true)] {
            let screen=host.convert(point,from:host.canvas)
            guard host.bounds.contains(screen) else { return XCTFail("Expected ink must be visible: \(phase) \(screen)") }
            let color=pixel(image,at:screen)
            if present { XCTAssertGreaterThan(color[2],150,phase); XCTAssertLessThan(color[0],100,phase) }
            else { XCTAssertLessThan(Int(color[2])-Int(color[0]),25,phase) }
        }
    }
    func testSelectionPDFCloneAndDeleteRenderInPageCoordinatesAtEveryCropRotation() async throws {
        let root=try directory(), bytes=try PDFFixture.data(), prepared=try await PDFImporter().prepare(data:bytes,filename:"source.pdf")
        let store=DocumentStore(directory:root.appendingPathComponent("note"))
        try FileManager.default.createDirectory(at:root.appendingPathComponent("note/assets"),withIntermediateDirectories:true)
        try bytes.write(to:root.appendingPathComponent("note/\(prepared.asset.relativePath)"))
        var ink=testInk(); for i in ink.points.indices { ink.points[i].y=120 }
        var doc=NoteDocument(title:"Clone pixels",pages:prepared.pages,pdfAssets:[prepared.asset])
        for i in doc.pages.indices { var copy=ink; copy.id=UUID(); doc.pages[i].strokes=[copy] }
        try await store.save(doc)
        let session=EditorSession(store:store,saveDelay:.seconds(60),exportRegistry:ExportFileRegistry(root:root.appendingPathComponent("exports"))); await session.loadIfNeeded()
        for i in 0..<4 {
            await session.selectPage(i); try selectAll(session); _=try session.duplicateSelectedInk(dx:20,dy:20)
            let host=PageZoomHost(frame:CGRect(x:0,y:0,width:834,height:900)), page=try XCTUnwrap(session.currentPage)
            host.configurePage(size:CGSize(width:page.width,height:page.height),pdfPage:session.currentPDFPage); host.layoutIfNeeded()
            let reference=CanvasReference(); reference.canvas=host.canvas
            let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:host.canvas)
            coordinator.apply(session.drawing,to:host.canvas)
            let scroll=try XCTUnwrap(host.subviews.first as? UIScrollView)
            for zoom in [1.0,2.0,5.0] {
                scroll.zoomScale=scroll.minimumZoomScale*zoom
                let a=host.lasso.convert(host.convert(CGPoint(x:130,y:120),from:host.canvas),from:host)
                let b=host.lasso.convert(host.convert(CGPoint(x:150,y:140),from:host.canvas),from:host)
                XCTAssertEqual(b.x-a.x,20,accuracy:0.0001); XCTAssertEqual(b.y-a.y,20,accuracy:0.0001)
                try await assertScreenInk(host,original:true,phase:"selection-screen-clone-r\(i*90)-z\(zoom)")
            }
        }
        let export1=await session.exportPDF(), first=try XCTUnwrap(export1), pdf1=try XCTUnwrap(PDFDocument(url:first.url))
        for i in 0..<4 {
            let page=try XCTUnwrap(pdf1.page(at:i)), image=renderPDFPage(page,size:try PDFGeometry(page:page).size)
            for point in [CGPoint(x:130,y:120),CGPoint(x:150,y:140)] { let color=pixel(image,at:point); XCTAssertGreaterThan(color[2],150); XCTAssertLessThan(color[0],100) }
            await session.selectPage(i)
            try session.selectInk(polygon:[.init(x:95,y:115),.init(x:105,y:115),.init(x:105,y:125),.init(x:95,y:125)])
            XCTAssertEqual(session.selectedStrokeIDs.count,1); _=try session.deleteSelectedInk()
            let host=PageZoomHost(frame:CGRect(x:0,y:0,width:834,height:900)), current=try XCTUnwrap(session.currentPage)
            host.configurePage(size:CGSize(width:current.width,height:current.height),pdfPage:session.currentPDFPage)
            let reference=CanvasReference(); reference.canvas=host.canvas
            let coordinator=NoteCanvas.Coordinator(session:session,reference:reference); coordinator.attach(to:host.canvas)
            coordinator.apply(session.drawing,to:host.canvas)
            try await assertScreenInk(host,original:false,phase:"selection-screen-delete-r\(i*90)")
        }
        let export2=await session.exportPDF(), second=try XCTUnwrap(export2), pdf2=try XCTUnwrap(PDFDocument(url:second.url))
        for i in 0..<4 {
            let page=try XCTUnwrap(pdf2.page(at:i)), image=renderPDFPage(page,size:try PDFGeometry(page:page).size)
            let color=pixel(image,at:CGPoint(x:150,y:140)), old=pixel(image,at:CGPoint(x:130,y:120)), outline=pixel(image,at:CGPoint(x:150,y:128))
            XCTAssertGreaterThan(color[2],150); XCTAssertLessThan(color[0],100)
            XCTAssertLessThan(Int(old[2])-Int(old[0]),25); XCTAssertEqual(outline[0],outline[2])
        }
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("note/\(prepared.asset.relativePath)")),bytes)
        try await session.exportRegistry.release(first.lease); try await session.exportRegistry.release(second.lease)
    }
    func testGenerateActualSelectionV3Fixtures() async throws {
        let root=try directory(), store=try await fixture(in:root), session=EditorSession(store:store,saveDelay:.seconds(60)); await session.loadIfNeeded()
        let source=try XCTUnwrap(session.document); try selectAll(session); _=try session.duplicateSelectedInk(dx:20,dy:20)
        let duplicated=try XCTUnwrap(session.document), clones=Array(duplicated.pages[1].strokes.dropFirst(source.pages[1].strokes.count))
        try selectOriginalPDFInk(session); _=try session.deleteSelectedInk(); let deleted=try XCTUnwrap(session.document)
        let output=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("PortableInkGenerated")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        for (name,document) in [("selection-source",source),("selection-duplicated",duplicated),("selection-deleted",deleted)] {
            try DocumentCodec.encode(document).write(to:output.appendingPathComponent(name+".json"),options:.atomic)
        }
        let manifest:[[String:Any]]=[
            ["kind":"duplicateStrokes","pageID":source.pages[1].id.uuidString,"strokeIDs":source.pages[1].strokes.map { $0.id.uuidString },"newIDs":clones.map { $0.id.uuidString },"dx":20,"dy":20,"expectedRevision":source.revision],
            ["kind":"deleteStrokes","pageID":source.pages[1].id.uuidString,"strokeIDs":source.pages[1].strokes.map { $0.id.uuidString },"expectedRevision":duplicated.revision]]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("selection-commands.json"),options:.atomic)
        XCTAssertEqual(deleted.pages[1].strokes,clones)
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
        canvas.undoManager?.undo() // UIKit/system Undo must obey the same save guard.
        XCTAssertEqual(session.document,expected); XCTAssertTrue(canvas.undoManager?.canUndo ?? false)
        let failedBackup=await session.exportBackup(); XCTAssertNil(failedBackup)
        fault.disarm(); session.retrySave(); await session.flush(); XCTAssertEqual(session.saveState,.saved)
        let disk=try await store.load(); XCTAssertEqual(disk?.document,expected)
        let exported=await session.exportBackup(), file=try XCTUnwrap(exported), prepared=try await BackupFileAccess().prepare(url:file.url)
        defer { try? FileManager.default.removeItem(at:prepared.stagingDirectory) }
        XCTAssertEqual(prepared.document,expected); try await registry.release(file.lease)
        canvas.undoManager?.undo()
        XCTAssertEqual(session.currentPage?.strokes[0].transform.tx,5)
        fault.arm(); await session.flush()
        guard case .failed = session.saveState else { return XCTFail("Undo save must fail") }
        let undone=session.document
        canvas.undoManager?.redo()
        XCTAssertEqual(session.document,undone); XCTAssertTrue(canvas.undoManager?.canRedo ?? false)
        fault.disarm(); session.retrySave(); await session.flush()
        canvas.undoManager?.redo()
        XCTAssertEqual(session.currentPage?.strokes,expected.pages[0].strokes)
        await session.flush(); XCTAssertEqual(session.saveState,.saved)
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
        XCTAssertThrowsError(try session.translateSelectedInk(dx:10,dy:10)); canvas.undoManager?.undo()
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
