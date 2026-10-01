import MiNoteCore
import PDFKit
import XCTest
@testable import MiNote

@MainActor final class PDFImportTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testImportKeepsOriginalBytesAndAllPageGeometry() async throws {
        let bytes = try PDFFixture.data()
        // Shared with the system Files picker UI test, in the test app's Documents.
        let sample = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MiNote-Sample.pdf")
        try bytes.write(to: sample, options: .atomic)
        let prepared = try await PDFImporter().prepare(url: sample)
        XCTAssertEqual(prepared.data, bytes)
        XCTAssertEqual(prepared.asset.pageCount, 4)
        XCTAssertEqual(prepared.pages.map(\.width), [300, 450, 300, 450])
        XCTAssertEqual(prepared.pages.map(\.height), [450, 300, 450, 300])
        XCTAssertEqual(prepared.pages.map { $0.pdfSource?.rotation }, [0, 90, 180, 270])
        XCTAssertEqual(prepared.pages[0].pdfSource?.cropBox.x, 40)
    }

    func testBrokenTruncatedAndLockedPDFsCannotImport() async throws {
        let importer = PDFImporter()
        for bytes in [Data("not pdf".utf8), Data(try PDFFixture.data().dropLast(40))] {
            do { _ = try await importer.prepare(data: bytes, filename: "broken.pdf"); XCTFail("Must reject invalid PDF") }
            catch { XCTAssertTrue(error is PDFError) }
        }
        let document = try XCTUnwrap(PDFDocument(data: PDFFixture.data()))
        let encrypted = try XCTUnwrap(document.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption: "secret", PDFDocumentWriteOption.ownerPasswordOption: "owner"]))
        do { _ = try await importer.prepare(data: encrypted, filename: "locked.pdf"); XCTFail("Must reject locked PDF") }
        catch { guard case PDFError.locked = error else { return XCTFail("Expected locked error: \(error)") } }
    }

    func testSessionPageInkSurvivesNavigationAndRelaunch() async throws {
        let url = try directory()
        let store = DocumentStore(directory: url)
        let session = EditorSession(store: store, saveDelay: .seconds(5))
        await session.loadIfNeeded()
        let originalID = session.document?.pages[0].id
        let pdfURL = url.appendingPathComponent("source.pdf")
        try PDFFixture.data().write(to: pdfURL)
        await session.importPDF(from: pdfURL)
        XCTAssertNil(session.operationError)
        XCTAssertEqual(session.document?.pages.count, 5)
        XCTAssertEqual(session.currentPageIndex, 1)
        session.receiveDrawing(try InkAdapter.decode([testInk()]))
        let firstID = session.document?.pages[1].strokes.first?.id
        session.selectPage(2)
        XCTAssertEqual(session.strokeCount, 0)
        session.receiveDrawing(try InkAdapter.decode([testInk()]))
        XCTAssertNotEqual(session.document?.pages[2].strokes.first?.id, firstID)
        session.selectPage(1)
        XCTAssertEqual(session.strokeCount, 1)
        XCTAssertEqual(session.document?.pages[1].strokes.first?.id, firstID)
        session.selectPage(2)
        await session.flush()
        let reopened = EditorSession(store: DocumentStore(directory: url))
        await reopened.loadIfNeeded()
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.currentPageIndex, 2)
        XCTAssertEqual(reopened.strokeCount, 1)
        XCTAssertEqual(reopened.document?.pages[0].id, originalID)
        XCTAssertEqual(reopened.document?.pages[1].strokes.first?.id, firstID)
    }

    func testFailedImportLeavesExistingInkEditable() async throws {
        let url = try directory()
        let session = EditorSession(store: DocumentStore(directory: url))
        await session.loadIfNeeded()
        session.receiveDrawing(try InkAdapter.decode([testInk()]))
        await session.flush()
        let before = session.document
        let source = url.appendingPathComponent("broken.pdf")
        try Data("broken".utf8).write(to: source)
        await session.importPDF(from: source)
        XCTAssertNotNil(session.operationError)
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.strokeCount, 1)
        XCTAssertFalse(session.isProcessing)
    }
}

func testInk(x: Double = 100) -> InkStroke {
    InkStroke(tool: .pen, color: InkColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1),
        points: [InkPoint(x: x, y: 100, timeOffset: 0, width: 8, height: 8, opacity: 1, force: 1, azimuth: 0, altitude: 1),
                 InkPoint(x: x + 60, y: 140, timeOffset: 0.2, width: 8, height: 8, opacity: 1, force: 1, azimuth: 0, altitude: 1)],
        randomSeed: 12, creationTime: 100)
}
