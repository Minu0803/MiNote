import MiNoteCore
import PencilKit

enum InkSelection {
    static func selectedIDs(in drawing: PKDrawing, portable: [InkStroke], polygon: [SelectionPoint]) throws -> Set<UUID> {
        guard try InkAdapter.encode(drawing,preserving:portable) == portable else { throw DocumentError.staleRevision }
        // Validate the polygon even when there are no strokes.
        _ = try SelectionGeometry.intersects(polyline:[],polygon:polygon)
        var selected = Set<UUID>()
        for (native, saved) in zip(drawing.strokes,portable) {
            let t=native.transform
            // Frobenius norm bounds the affine linear part's stretch in any
            // direction. Sample at most 2 page points after the transform.
            let stretch=max(1,hypot(hypot(t.a,t.b),hypot(t.c,t.d)))
            guard stretch.isFinite else { throw DocumentError.invalidDocument("선택 좌표 범위") }
            let points = native.path.interpolatedPoints(by:.distance(2/stretch)).map { point in
                let p = point.location.applying(native.transform)
                return SelectionPoint(x:p.x,y:p.y)
            }
            if try SelectionGeometry.intersects(polyline:points,polygon:polygon) { selected.insert(saved.id) }
        }
        return selected
    }
}

struct InkTransition {
    let pageID: UUID
    let generation: UUID
    let before: [InkStroke]
    let after: [InkStroke]
    let beforeDrawing: PKDrawing
    let afterDrawing: PKDrawing
}
