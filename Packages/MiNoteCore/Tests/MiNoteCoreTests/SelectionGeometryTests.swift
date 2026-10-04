import Foundation
import XCTest
@testable import MiNoteCore

final class SelectionGeometryTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> SelectionPoint { SelectionPoint(x: x, y: y) }
    func testClosedAreaBoundaryCrossingAndOutsideHaveLiteralResults() throws {
        let square = [point(0,0), point(4,0), point(4,4), point(0,4)]
        let cases: [([SelectionPoint], Bool)] = [([point(2,2)], true), ([point(0,2)], true), ([point(4,4)], true),
            ([point(-1,2),point(5,2)], true), ([point(-1,0),point(5,0)], true), ([point(-1,5),point(5,5)], false),
            ([point(-1,-1),point(-1,5)], false), ([], false)]
        for (line, want) in cases { XCTAssertEqual(try SelectionGeometry.intersects(polyline: line, polygon: square), want) }
    }
    func testSelfCrossingEvenOddAndExplicitClosingVertex() throws {
        let bow = [point(0,0),point(4,4),point(0,4),point(4,0)]
        XCTAssertTrue(try SelectionGeometry.intersects(polyline: [point(2,1)], polygon: bow))
        XCTAssertFalse(try SelectionGeometry.intersects(polyline: [point(0.5,2)], polygon: bow))
        XCTAssertTrue(try SelectionGeometry.intersects(polyline: [point(2,2)], polygon: bow + [bow[0]]))
    }
    func testInvalidCoordinatesOrTooFewDistinctVerticesFailExplicitly() throws {
        let square = [point(0,0),point(4,0),point(4,4),point(0,4)]
        for polygon in [[], [point(1,1)], [point(1,1),point(2,2),point(1,1)], [point(0,0),point(.nan,2),point(2,2)]] {
            XCTAssertThrowsError(try SelectionGeometry.intersects(polyline: [], polygon: polygon))
        }
        XCTAssertThrowsError(try SelectionGeometry.intersects(polyline: [point(.infinity, 0)], polygon: square))
    }
    func testLargeFiniteCoordinatesDoNotOverflowIntersectionArithmetic() throws {
        let square = [point(-1e308,-1e308),point(1e308,-1e308),point(1e308,1e308),point(-1e308,1e308)]
        XCTAssertTrue(try SelectionGeometry.intersects(polyline: [point(0,0)], polygon: square))
        XCTAssertFalse(try SelectionGeometry.intersects(polyline: [point(1.7e308,0)], polygon: square))
    }
}
