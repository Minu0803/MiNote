import Foundation
import XCTest
@testable import MiNoteCore

final class DocumentCodecTests: XCTestCase {
    func testRoundTripRetainsEditableGeometryAndIdentity() throws {
        var document = NoteDocument.blank()
        let stroke = fixtureStroke()
        document.pages[0].strokes = [stroke]
        document.revision = 42
        let data = try DocumentCodec.encode(document)
        let decoded = try DocumentCodec.decode(data)
        XCTAssertEqual(decoded, document)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PKDrawing"))
    }

    func testSchemaV1WithoutSecondaryScaleUsesTheOriginalDefault() throws {
        let encoded = try DocumentCodec.encode(NoteDocument(title: "legacy", pages: [NotePage(strokes: [fixtureStroke()])]))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var pages = try XCTUnwrap(json["pages"] as? [[String: Any]])
        var strokes = try XCTUnwrap(pages[0]["strokes"] as? [[String: Any]])
        var points = try XCTUnwrap(strokes[0]["points"] as? [[String: Any]])
        points[0].removeValue(forKey: "secondaryScale")
        strokes[0]["points"] = points
        pages[0]["strokes"] = strokes
        json["pages"] = pages
        json["schemaVersion"] = 1
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try DocumentCodec.decode(legacyData)
        XCTAssertEqual(decoded.pages[0].strokes[0].points[0].secondaryScale, 1)
    }

    func testLegacyDocumentMigratesWithoutLosingInkOrIDs() throws {
        var original = NoteDocument.blank()
        original.revision = 27
        original.pages[0].strokes = [fixtureStroke()]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentCodec.encode(original)) as? [String: Any])
        json["schemaVersion"] = 1
        let migrated = try DocumentCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.id, original.id)
        XCTAssertEqual(migrated.revision, 27)
        XCTAssertEqual(migrated.pages, original.pages)
    }

    func testMultiplePageRoundTripAndDuplicatePageRejection() throws {
        var document = NoteDocument.blank()
        document.pages.append(NotePage(width: 300, height: 450, strokes: [fixtureStroke()]))
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(document)), document)
        document.pages.append(document.pages[0])
        XCTAssertThrowsError(try DocumentCodec.encode(document))
    }

    func testFutureSchemaIsDistinguishedFromCorruption() throws {
        let data = Data(#"{"schemaVersion":99}"#.utf8)
        XCTAssertThrowsError(try DocumentCodec.decode(data)) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedSchema(99))
        }
    }

    func testInvalidPageDimensionsAreRejected() {
        var document = NoteDocument.blank()
        document.pages[0].width = 0
        XCTAssertThrowsError(try DocumentCodec.encode(document))
    }

    func testDuplicateStrokeIDsAreRejected() {
        var document = NoteDocument.blank()
        let stroke = fixtureStroke()
        document.pages[0].strokes = [stroke, stroke]
        XCTAssertThrowsError(try DocumentCodec.encode(document))
    }

    func testNonFiniteCoordinatesAndEmptyStrokeAreRejected() {
        var document = NoteDocument.blank()
        var stroke = fixtureStroke()
        stroke.points[0].x = .infinity
        document.pages[0].strokes = [stroke]
        XCTAssertThrowsError(try DocumentCodec.encode(document))
        stroke.points = []
        document.pages[0].strokes = [stroke]
        XCTAssertThrowsError(try DocumentCodec.encode(document))
    }
}

func fixtureStroke(id: UUID = UUID()) -> InkStroke {
    InkStroke(id: id, tool: .pen, color: InkColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
              points: [InkPoint(x: 10, y: 20, timeOffset: 0, width: 2, height: 3,
                                opacity: 1, force: 0.6, azimuth: 0.2, altitude: 1.1)],
              transform: .identity, randomSeed: 17, creationTime: 100)
}
