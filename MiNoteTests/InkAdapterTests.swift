import XCTest
import PencilKit
import MiNoteCore
@testable import MiNote

@MainActor final class InkAdapterTests: XCTestCase {
    func testRoundTripKeepsControlPointsStyleAndIdentity() throws {
        let original = PKDrawing(strokes: [sampleStroke()])
        let encoded = try InkAdapter.encode(original, preserving: [])
        let restored = try InkAdapter.decode(encoded)
        let second = try InkAdapter.encode(restored, preserving: encoded)
        XCTAssertEqual(second, encoded)
        XCTAssertEqual(second[0].points.count, 3)
        XCTAssertEqual(second[0].points[1].x, 30, accuracy: 0.01)
        XCTAssertEqual(second[0].points[1].force, 0.7, accuracy: 0.01)
        XCTAssertEqual(second[0].transform.tx, 5, accuracy: 0.01)
        XCTAssertEqual(second[0].randomSeed, 42)
        XCTAssertEqual(second[0].points[1].secondaryScale, 1, accuracy: 0.01)
    }

    func testNonDefaultSecondaryScaleSurvivesRoundTrip() throws {
        let source = sampleStroke()
        let points = source.path.enumerated().map { index, point in
            PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: point.size,
                          opacity: point.opacity, force: point.force, azimuth: point.azimuth,
                          altitude: point.altitude, secondaryScale: index == 1 ? 1.7 : 1)
        }
        let stroke = PKStroke(ink: source.ink, path: PKStrokePath(controlPoints: points, creationDate: source.path.creationDate),
                              transform: source.transform, randomSeed: source.randomSeed)
        let saved = try InkAdapter.encode(PKDrawing(strokes: [stroke]), preserving: [])
        let restored = try InkAdapter.decode(saved)
        let encodedAgain = try InkAdapter.encode(restored, preserving: saved)
        XCTAssertEqual(encodedAgain[0].points[1].secondaryScale, 1.7, accuracy: 0.01)
    }

    func testSurvivingStrokeKeepsIDAfterAnotherStrokeIsErased() throws {
        let first = sampleStroke()
        let second = sampleStroke(offset: 50)
        let encoded = try InkAdapter.encode(PKDrawing(strokes: [first, second]), preserving: [])
        let remaining = try InkAdapter.encode(PKDrawing(strokes: [second]), preserving: encoded)
        XCTAssertEqual(remaining[0].id, encoded[1].id)
    }

    func testIdenticalStrokesHaveDistinctPersistentIDs() throws {
        let stroke = sampleStroke()
        let encoded = try InkAdapter.encode(PKDrawing(strokes: [stroke, stroke]), preserving: [])
        XCTAssertNotEqual(encoded[0].id, encoded[1].id)
        let restored = try InkAdapter.decode(encoded)
        XCTAssertEqual(try InkAdapter.encode(restored, preserving: encoded).map(\.id), encoded.map(\.id))
    }

    func testUnsupportedPencilAndMaskAreRejected() throws {
        let pencil = sampleStroke(ink: .pencil)
        XCTAssertThrowsError(try InkAdapter.encode(PKDrawing(strokes: [pencil]), preserving: []))
        var masked = sampleStroke()
        masked.mask = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertThrowsError(try InkAdapter.encode(PKDrawing(strokes: [masked]), preserving: []))
    }

    func testMarkerAndEmptyDrawingRoundTrip() throws {
        let marker = try InkAdapter.encode(PKDrawing(strokes: [sampleStroke(ink: .marker)]), preserving: [])
        XCTAssertEqual(marker[0].tool, .marker)
        XCTAssertEqual(try InkAdapter.decode([]).strokes.count, 0)
    }
}

@MainActor func sampleStroke(offset: CGFloat = 0, ink: PKInk.InkType = .pen) -> PKStroke {
    let points = (0..<3).map { index in
        PKStrokePoint(location: CGPoint(x: 10 + index * 20, y: 20 + Int(offset)),
                      timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 4),
                      opacity: 1, force: 0.7, azimuth: 0.4, altitude: 1.0)
    }
    return PKStroke(ink: PKInk(ink, color: UIColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)),
                    path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1234)),
                    transform: CGAffineTransform(translationX: 5, y: 6), randomSeed: 42)
}
