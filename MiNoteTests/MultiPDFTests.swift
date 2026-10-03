import MiNoteCore
import PDFKit
import UIKit
import XCTest
@testable import MiNote

@MainActor final class MultiPDFTests: XCTestCase {
    func testPreparedPagesReferenceOwnAssetAndSubsetMappingIsValid() async throws {
        let bytes = try PDFFixture.data()
        let a = try await PDFImporter().prepare(data: bytes, filename: "same.pdf")
        let b = try await PDFImporter().prepare(data: PDFFixture.data(rotations: [90]), filename: "same.pdf")
        XCTAssertNotEqual(a.asset.id, b.asset.id)
        XCTAssertTrue(a.pages.allSatisfy { $0.pdfSource?.assetID == a.asset.id })
        XCTAssertTrue(b.pages.allSatisfy { $0.pdfSource?.assetID == b.asset.id })
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("a.pdf"); try bytes.write(to: url)
        var duplicate = a.pages[2]; duplicate.id = UUID()
        XCTAssertNoThrow(try PDFValidation.open(url: url, asset: a.asset, referencedPages: [a.pages[2], duplicate]))
        XCTAssertThrowsError(try PDFValidation.open(url: url, asset: b.asset, referencedPages: b.pages))
    }

    func testExportDuplicatedAndReorderedPDFPagesHasOnlyTheirOwnInk() async throws {
        let root = try temporaryDirectory()
        let bytesA = try PDFFixture.data(), bytesB = try PDFFixture.data(rotations: [90])
        let a = try await PDFImporter().prepare(data: bytesA, filename: "same.pdf")
        let b = try await PDFImporter().prepare(data: bytesB, filename: "same.pdf")
        let urlA = root.appendingPathComponent("a.pdf"), urlB = root.appendingPathComponent("b.pdf")
        try bytesA.write(to: urlA); try bytesB.write(to: urlB)
        var first = a.pages[0]; first.strokes = [testInk(x: 40)]
        var copy = a.pages[0]; copy.id = UUID(); copy.strokes = [testInk(x: 180)]
        let ruled = NotePage(paper: .ruled), grid = NotePage(paper: .grid)
        let document = NoteDocument(title: "combined", pages: [copy, b.pages[0], first, ruled, grid],
            pdfAssets: [a.asset, b.asset], deletedPages: [DeletedPage(page: a.pages[3], originalIndex: 0, deletedAt: 100)])
        let output = root.appendingPathComponent("export.pdf")
        try PDFExporter.export(document, sourceURLs: [a.asset.id: urlA, b.asset.id: urlB], destination: output)
        let pdf = try XCTUnwrap(PDFDocument(url: output)); XCTAssertEqual(pdf.pageCount, 5)
        XCTAssertEqual(pdf.page(at: 1)?.rotation, 90)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("MiNote PDF fixture") == true)
        let copied = renderPDFPage(try XCTUnwrap(pdf.page(at: 0)), size: CGSize(width: 300, height: 450))
        let original = renderPDFPage(try XCTUnwrap(pdf.page(at: 2)), size: CGSize(width: 300, height: 450))
        XCTAssertLessThan(pixel(copied, at: CGPoint(x: 210, y: 120))[0], 100)
        XCTAssertGreaterThan(pixel(copied, at: CGPoint(x: 70, y: 120))[0], 200, "Other duplicate's ink must not leak")
        XCTAssertLessThan(pixel(original, at: CGPoint(x: 70, y: 120))[0], 100)
        XCTAssertGreaterThan(pixel(original, at: CGPoint(x: 210, y: 120))[0], 200)
        for (i, style) in [(3, PaperStyle.ruled), (4, .grid)] {
            let rendered = renderPDFPage(try XCTUnwrap(pdf.page(at: i)), size: CGSize(width: ruled.width, height: ruled.height))
            XCTAssertLessThan(pixel(rendered, at: CGPoint(x: 60, y: 24))[0], 252, "Horizontal paper line")
            if style == .grid { XCTAssertLessThan(pixel(rendered, at: CGPoint(x: 24, y: 60))[0], 252) }
        }
        XCTAssertEqual(try Data(contentsOf: urlA), bytesA); XCTAssertEqual(try Data(contentsOf: urlB), bytesB)
        try PDFExporter.export(document, sourceURLs: [a.asset.id: urlA, b.asset.id: urlB], destination: root.appendingPathComponent("again.pdf"))
        XCTAssertEqual(try Data(contentsOf: urlA), bytesA)
        XCTAssertThrowsError(try PDFExporter.export(document, sourceURLs: [a.asset.id: urlA], destination: output))
        XCTAssertThrowsError(try PDFExporter.export(document, sourceURLs: [a.asset.id: urlA, b.asset.id: urlB], destination: urlB))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
}
