import PencilKit
import PDFKit
import XCTest
@testable import MiNoteCore
@testable import MiNote

@MainActor final class PageEditorTests: XCTestCase {
    func testPageCommandFlushesLatestInkAndKeepsSessionOnFailure() async throws {
        let root = try directory(), store = DocumentStore(directory: root)
        let session = EditorSession(store: store, saveDelay: .seconds(60)); await session.loadIfNeeded()
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        let id = try XCTUnwrap(session.currentPage?.id)
        await session.applyPageCommand(.duplicate(id))
        XCTAssertNil(session.operationError); XCTAssertEqual(session.document?.pages.count, 2)
        XCTAssertEqual(session.strokeCount, 1); XCTAssertNotEqual(session.currentPage?.id, id)
        let currentID = try XCTUnwrap(session.currentPage?.id)
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke(ink: .pencil)]))
        await session.applyPageCommand(.delete(currentID))
        XCTAssertEqual(session.currentPage?.id, currentID); XCTAssertEqual(session.document?.pages.count, 2)
        XCTAssertEqual(session.strokeCount, 1); XCTAssertNotNil(session.operationError)
        guard case .failed = session.saveState else { return XCTFail("Unsupported ink must remain") }
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke(), sampleStroke(offset: 80)])); await session.flush()
        let backup = root.appendingPathComponent("document.backup.json")
        try FileManager.default.removeItem(at: backup); try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        let snapshot = session.document
        await session.applyPageCommand(.delete(currentID))
        XCTAssertEqual(session.document, snapshot); XCTAssertEqual(session.strokeCount, 2)
        XCTAssertNotNil(session.operationError); XCTAssertFalse(session.isProcessing)
    }

    func testPDFAssetSwitchAndRestoredPageRemainEditable() async throws {
        let root = try directory(), session = EditorSession(store: DocumentStore(directory: root))
        await session.loadIfNeeded()
        let a = root.appendingPathComponent("a.pdf"), b = root.appendingPathComponent("b.pdf")
        try PDFFixture.data().write(to: a); try PDFFixture.data(rotations: [90]).write(to: b)
        await session.importPDF(from: a)
        let pageA = try XCTUnwrap(session.currentPage)
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        await session.importPDF(from: b)
        XCTAssertNil(session.operationError); XCTAssertEqual(session.document?.pdfAssets.count, 2)
        let pageB = try XCTUnwrap(session.currentPage)
        XCTAssertNotEqual(pageA.pdfSource?.assetID, pageB.pdfSource?.assetID)
        XCTAssertEqual(session.currentPDFPage?.rotation, 90)
        await session.selectPage(1); XCTAssertEqual(session.strokeCount, 1)
        XCTAssertEqual(session.currentPDFPage?.rotation, 0)
        await session.applyPageCommand(.duplicate(pageA.id))
        let copied = try XCTUnwrap(session.currentPage)
        XCTAssertEqual(copied.pdfSource, pageA.pdfSource); XCTAssertEqual(session.strokeCount, 1)
        session.receiveDrawing(PKDrawing(strokes: [sampleStroke(), sampleStroke(offset: 80)]))
        await session.applyPageCommand(.move(copied.id, toIndex: 0))
        XCTAssertEqual(session.currentPageIndex, 0); XCTAssertEqual(session.strokeCount, 2)
        await session.applyPageCommand(.delete(copied.id))
        XCTAssertNotEqual(session.currentPage?.id, copied.id)
        await session.applyPageCommand(.restore(copied.id))
        XCTAssertEqual(session.currentPage?.id, copied.id); XCTAssertEqual(session.strokeCount, 2)
        let fresh = EditorSession(store: DocumentStore(directory: root)); await fresh.loadIfNeeded()
        XCTAssertEqual(fresh.document, session.document); XCTAssertEqual(fresh.strokeCount, 2)
        XCTAssertEqual(fresh.currentPDFPage?.rotation, 0)
        await fresh.selectPage(2); XCTAssertEqual(fresh.currentPage?.id, pageA.id); XCTAssertEqual(fresh.strokeCount, 1)
    }

    func testLateDrawingDuringFlushOrCommitBlocksCommandWithoutLosingInk() async throws {
        for readNumber in [1, 3] {
            for unsupported in [false, true] {
                let root = try directory(), delivery = LatePageDrawing()
                delivery.unsupported = unsupported
                let reads = PageReadGate(trigger: readNumber)
                let store = DocumentStore(directory: root, dataReader: { url in
                    let data = try Data(contentsOf: url)
                    if url.lastPathComponent == "document.json", reads.shouldDeliver() {
                        let done = DispatchSemaphore(value: 0)
                        Task { @MainActor in delivery.deliver(); done.signal() }
                        _ = done.wait(timeout: .now() + 5)
                    }
                    return data
                })
                let session = EditorSession(store: store, saveDelay: .seconds(60)); await session.loadIfNeeded()
                session.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
                let id = try XCTUnwrap(session.currentPage?.id)
                delivery.editor = session; reads.arm()
                await session.applyPageCommand(.duplicate(id))
                XCTAssertEqual(session.currentPage?.id, id); XCTAssertEqual(session.document?.pages.count, 1)
                XCTAssertNotNil(session.operationError); XCTAssertEqual(session.strokeCount, unsupported ? 1 : 2)
                if unsupported {
                    guard case .failed = session.saveState else { return XCTFail("Unsupported late callback must remain visible") }
                } else {
                    session.retrySave(); await session.flush()
                    let disk = try await store.load(); XCTAssertEqual(disk?.document, session.document)
                    XCTAssertEqual(disk?.document.pages[0].strokes.count, 2)
                }
            }
        }
    }

    func testThumbnailAndPDFCachesAreBoundedAndStaleResultsAreNotPublished() async throws {
        let root = try directory(), session = EditorSession(store: DocumentStore(directory: root))
        await session.loadIfNeeded()
        for i in 0..<3 {
            let url = root.appendingPathComponent("p\(i).pdf"); try PDFFixture.data(rotations: [i * 90]).write(to: url)
            await session.importPDF(from: url)
        }
        for _ in 0..<25 { await session.applyPageCommand(.insert(after: try XCTUnwrap(session.currentPage?.id), paper: .grid)) }
        let doc = try XCTUnwrap(session.document)
        for page in doc.pages {
            let image = await session.thumbnail(pageID: page.id, expectedRevision: doc.revision)
            XCTAssertNotNil(image); XCTAssertLessThanOrEqual(image?.cgImage?.width ?? 0, 256)
            XCTAssertLessThanOrEqual(image?.cgImage?.height ?? 0, 256)
        }
        XCTAssertLessThanOrEqual(session.cachedPDFCount, 2); XCTAssertLessThanOrEqual(session.cachedThumbnailCount, 24)
        let stale = await session.thumbnail(pageID: doc.pages[0].id, expectedRevision: doc.revision - 1)
        XCTAssertNil(stale)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
}

@MainActor private final class LatePageDrawing {
    var editor: EditorSession?
    var unsupported = false
    func deliver() {
        editor?.receiveDrawing(PKDrawing(strokes: unsupported ? [sampleStroke(ink: .pencil)] : [sampleStroke(), sampleStroke(offset: 80)]))
    }
}
private final class PageReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var armed = false
    private let trigger: Int
    init(trigger: Int) { self.trigger = trigger }
    func arm() { lock.lock(); defer { lock.unlock() }; armed = true; count = 0 }
    func shouldDeliver() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard armed else { return false }; count += 1
        if count == trigger { armed = false; return true }; return false
    }
}
