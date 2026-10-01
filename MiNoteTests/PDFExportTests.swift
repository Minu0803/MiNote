import MiNoteCore
import PDFKit
import PencilKit
import XCTest
@testable import MiNote

@MainActor final class PDFExportTests: XCTestCase {
    func testExportKeepsSourceGeometryTextAndAlignedInk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try PDFFixture.data()
        let source = directory.appendingPathComponent("source.pdf")
        try bytes.write(to: source)
        let prepared = try await PDFImporter().prepare(data: bytes, filename: "source.pdf")
        var document = NoteDocument(title: "export", pages: prepared.pages, pdfAsset: prepared.asset)
        for index in document.pages.indices { document.pages[index].strokes = [testInk()] }
        let destination = directory.appendingPathComponent("annotated.pdf")
        let snapshot = document
        try await Task.detached {
            try PDFExporter.export(snapshot, sourceURL: source, destination: destination)
        }.value
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let original = try XCTUnwrap(PDFDocument(data: bytes))
        let exported = try XCTUnwrap(PDFDocument(url: destination))
        XCTAssertEqual(exported.pageCount, 4)
        XCTAssertTrue(exported.string?.contains("MiNote PDF fixture") == true, "Original text must remain searchable")
        for index in 0..<4 {
            let before = try XCTUnwrap(original.page(at: index))
            let after = try XCTUnwrap(exported.page(at: index))
            let media = before.bounds(for: .mediaBox)
            XCTAssertEqual(after.bounds(for: .mediaBox).size, media.size)
            // PDFKit normalizes MediaBox origin; crop offset and visible size
            // must stay identical, rather than comparing unrelated raw origins.
            XCTAssertEqual(after.bounds(for: .cropBox), before.bounds(for: .cropBox).offsetBy(dx: -media.minX, dy: -media.minY))
            XCTAssertEqual(after.rotation, before.rotation)
            let size = try PDFGeometry(page: after).size
            let image = renderPDFPage(after, size: size)
            let color = pixel(image, at: CGPoint(x: 130, y: 120))
            XCTAssertGreaterThan(color[2], 150, "Ink at canonical point, rotation \(index * 90)")
            XCTAssertLessThan(color[0], 100)
        }
    }

    func testFailedOutputCannotChangeSourceOrExistingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try PDFFixture.data()
        let source = directory.appendingPathComponent("source.pdf")
        try bytes.write(to: source)
        let prepared = try await PDFImporter().prepare(data: bytes, filename: "source.pdf")
        let document = NoteDocument(title: "export", pages: prepared.pages, pdfAsset: prepared.asset)
        XCTAssertThrowsError(try PDFExporter.export(document, sourceURL: source, destination: source))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let destination = directory.appendingPathComponent("target.pdf")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        XCTAssertThrowsError(try PDFExporter.export(document, sourceURL: source, destination: destination))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
