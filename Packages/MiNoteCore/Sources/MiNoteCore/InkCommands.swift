import Foundation

/// Translation uses page coordinates; control points and linear transforms stay intact.
public enum InkCommands {
    public static func translate(strokeIDs: Set<UUID>, pageID: UUID, dx: Double, dy: Double,
                                 expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument {
        try DocumentCodec.validate(document)
        guard document.revision == expectedRevision else { throw DocumentError.staleRevision }
        guard dx.isFinite, dy.isFinite, let index = document.pages.firstIndex(where: { $0.id == pageID }),
              strokeIDs.isSubset(of: Set(document.pages[index].strokes.map(\.id))) else {
            throw DocumentError.invalidDocument("선택 획 또는 이동 좌표")
        }
        guard !strokeIDs.isEmpty, dx != 0 || dy != 0 else { return document }
        guard document.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
        var result = document
        for i in result.pages[index].strokes.indices where strokeIDs.contains(result.pages[index].strokes[i].id) {
            result.pages[index].strokes[i].transform.tx += dx
            result.pages[index].strokes[i].transform.ty += dy
        }
        result.revision += 1
        try DocumentCodec.validate(result)
        return result
    }
}
