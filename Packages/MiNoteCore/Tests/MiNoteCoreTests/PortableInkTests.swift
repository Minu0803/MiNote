import Foundation
import XCTest
@testable import MiNoteCore

final class PortableInkTests: XCTestCase {
    func testPencilKitFixtureSurvivesPortableCodec() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "source", withExtension: "json", subdirectory: "PortableInk"))
        let document = try DocumentCodec.decode(Data(contentsOf: url))
        XCTAssertEqual(document.revision, 40)
        XCTAssertEqual(document.pages.count, 5)
        XCTAssertEqual(document.pages[0].strokes.count, 4)
        XCTAssertEqual(document.pages[0].strokes[0].transform.tx, 5)
        XCTAssertEqual(document.pages[0].strokes[1].tool, .marker)
        XCTAssertNotEqual(document.pages[0].strokes[0].id, document.pages[0].strokes[2].id)
        XCTAssertEqual(document.pages[0].strokes[0].points, document.pages[0].strokes[2].points)
        XCTAssertEqual(document.pdfAsset?.pageCount, 4)
        XCTAssertEqual(document.pages[2].pdfSource?.rotation, 90)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(document)), document)
    }
}
