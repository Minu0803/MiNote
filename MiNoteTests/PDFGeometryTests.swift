import PDFKit
import XCTest
@testable import MiNote

@MainActor final class PDFGeometryTests: XCTestCase {
    // A wrong crop translation or rotation moves a source corner away from its ink point.
    func testCropOriginAndAllRotationsMapToKnownCanvasCorners() throws {
        let doc = try XCTUnwrap(PDFDocument(data: PDFFixture.data()))
        let expected: [CGPoint] = [CGPoint(x: 0, y: 450), CGPoint(x: 0, y: 0),
                                   CGPoint(x: 300, y: 0), CGPoint(x: 450, y: 300)]
        for index in 0..<4 {
            let geometry = try PDFGeometry(page: XCTUnwrap(doc.page(at: index)))
            let corner = CGPoint(x: 40, y: 70).applying(geometry.pdfToCanvas)
            XCTAssertEqual(corner.x, expected[index].x, accuracy: 0.001)
            XCTAssertEqual(corner.y, expected[index].y, accuracy: 0.001)
            XCTAssertEqual(geometry.size, index.isMultiple(of: 2) ? CGSize(width: 300, height: 450) : CGSize(width: 450, height: 300))
            let original = CGPoint(x: 120, y: 250)
            let restored = original.applying(geometry.pdfToCanvas).applying(geometry.pdfToCanvas.inverted())
            XCTAssertEqual(restored.x, original.x, accuracy: 0.001)
            XCTAssertEqual(restored.y, original.y, accuracy: 0.001)
        }
    }
}
