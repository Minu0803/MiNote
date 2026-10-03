import Foundation
import XCTest
@testable import MiNoteCore

final class PortableInkTests: XCTestCase {
    private func fixture(_ name: String) throws -> NoteDocument {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "PortableInk"))
        return try DocumentCodec.decode(Data(contentsOf: url))
    }

    func testIndependentJavaScriptAndBrowserEditsPreserveUntouchedData() throws {
        let source = try fixture("source")
        for name in ["edited", "browser-edited"] {
            let result = try fixture(name)
            XCTAssertEqual(result.id, source.id)
            XCTAssertEqual(result.revision, 43)
            XCTAssertEqual(result.title, source.title)
            XCTAssertEqual(result.pdfAssets, source.pdfAssets)
            XCTAssertEqual(result.lastOpenedPageID, source.lastOpenedPageID)
            XCTAssertEqual(Array(result.pages.dropFirst()), Array(source.pages.dropFirst()))
            let strokes = result.pages[0].strokes
            XCTAssertEqual(strokes.count, 4)
            var moved = source.pages[0].strokes[0]
            moved.transform.tx = 17; moved.transform.ty = -2
            XCTAssertEqual(strokes[0], moved)
            XCTAssertEqual(strokes[1], source.pages[0].strokes[1])
            XCTAssertEqual(strokes[2], source.pages[0].strokes[3])
            XCTAssertFalse(strokes.contains { $0.id == source.pages[0].strokes[2].id })
            XCTAssertEqual(strokes[3].tool, .pen)
            XCTAssertFalse(source.pages.flatMap(\.strokes).contains { $0.id == strokes[3].id })
            XCTAssertEqual(strokes[3].color, InkColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))
            XCTAssertEqual(strokes[3].randomSeed, 12)
            XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(result)), result)
        }
    }

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
        XCTAssertEqual(document.pdfAssets.first?.pageCount, 4)
        XCTAssertEqual(document.pages[2].pdfSource?.rotation, 90)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(document)), document)
    }
}
