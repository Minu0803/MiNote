import Foundation

public struct SelectionPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Closed even-odd polygon, including boundary contacts with stroke centre lines.
public enum SelectionGeometry {
    public static func intersects(polyline: [SelectionPoint], polygon: [SelectionPoint]) throws -> Bool {
        guard Set(polygon).count >= 3, (polygon + polyline).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw DocumentError.invalidDocument("올가미 좌표 또는 꼭짓점")
        }
        for point in polyline where contains(point, polygon: polygon) { return true }
        guard polyline.count > 1 else { return false }
        for i in 1..<polyline.count {
            for j in polygon.indices {
                if segmentsIntersect(polyline[i-1], polyline[i], polygon[j], polygon[(j+1) % polygon.count]) { return true }
            }
        }
        return false
    }

    private static func contains(_ p: SelectionPoint, polygon: [SelectionPoint]) -> Bool {
        var inside = false
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i+1) % polygon.count]
            let turn = orientation(a, b, p)
            if turn == 0 && inBounds(p, a, b) { return true }
            if (a.y > p.y) != (b.y > p.y), (b.y > a.y) == (turn > 0) { inside.toggle() }
        }
        return inside
    }
    private static func segmentsIntersect(_ a: SelectionPoint, _ b: SelectionPoint,
                                          _ c: SelectionPoint, _ d: SelectionPoint) -> Bool {
        let abC = orientation(a,b,c), abD = orientation(a,b,d), cdA = orientation(c,d,a), cdB = orientation(c,d,b)
        if abC == 0 && inBounds(c,a,b) || abD == 0 && inBounds(d,a,b) ||
            cdA == 0 && inBounds(a,c,d) || cdB == 0 && inBounds(b,c,d) { return true }
        return opposite(abC, abD) && opposite(cdA, cdB)
    }
    private static func opposite(_ a: Double, _ b: Double) -> Bool { a < 0 && b > 0 || a > 0 && b < 0 }
    private static func inBounds(_ p: SelectionPoint, _ a: SelectionPoint, _ b: SelectionPoint) -> Bool {
        p.x >= min(a.x,b.x) && p.x <= max(a.x,b.x) && p.y >= min(a.y,b.y) && p.y <= max(a.y,b.y)
    }
    private static func orientation(_ a: SelectionPoint, _ b: SelectionPoint, _ c: SelectionPoint) -> Double {
        // Scale each vector independently: neither subtraction nor products overflow.
        func direction(to p: SelectionPoint) -> (Double,Double) {
            var x = p.x-a.x, y = p.y-a.y
            if !x.isFinite || !y.isFinite { x = p.x/2-a.x/2; y = p.y/2-a.y/2 }
            let scale = max(abs(x),abs(y))
            return scale == 0 ? (0,0) : (x/scale,y/scale)
        }
        let u = direction(to: b), v = direction(to: c)
        return u.0*v.1-u.1*v.0
    }
}
