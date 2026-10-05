import Foundation

/// Translation uses page coordinates; control points and linear transforms stay intact.
public enum InkCommands {
    public static func paste(strokes: [InkStroke], pageID: UUID, dx: Double, dy: Double,
                             expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument {
        let index = try selectedPage([], pageID: pageID, revision: expectedRevision, document: document)
        guard dx.isFinite, dy.isFinite else { throw DocumentError.invalidDocument("붙여넣기 좌표") }
        guard !strokes.isEmpty else { return document }
        try InkClipboardCodec.validate(InkClipboardPayload(strokes: strokes))
        guard document.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
        var result = document
        for source in strokes {
            var pasted = source; pasted.id = UUID()
            pasted.transform.tx += dx; pasted.transform.ty += dy
            result.pages[index].strokes.append(pasted)
        }
        result.revision += 1
        try DocumentCodec.validate(result)
        _ = try InkClipboardCodec.bounds(of: Array(result.pages[index].strokes.suffix(strokes.count)))
        return result
    }

    public static func delete(strokeIDs: Set<UUID>, pageID: UUID,
                              expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument {
        let index = try selectedPage(strokeIDs, pageID: pageID, revision: expectedRevision, document: document)
        guard !strokeIDs.isEmpty else { return document }
        guard document.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
        var result = document
        result.pages[index].strokes.removeAll { strokeIDs.contains($0.id) }
        result.revision += 1
        try DocumentCodec.validate(result)
        return result
    }

    public static func duplicate(strokeIDs: Set<UUID>, pageID: UUID, dx: Double, dy: Double,
                                 expectedRevision: Int64, in document: NoteDocument) throws -> NoteDocument {
        let index = try selectedPage(strokeIDs, pageID: pageID, revision: expectedRevision, document: document)
        guard dx.isFinite, dy.isFinite else { throw DocumentError.invalidDocument("복제 좌표") }
        guard !strokeIDs.isEmpty else { return document }
        guard document.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
        var result = document
        for original in document.pages[index].strokes where strokeIDs.contains(original.id) {
            var clone = original
            clone.id = UUID()
            clone.transform.tx += dx; clone.transform.ty += dy
            result.pages[index].strokes.append(clone)
        }
        result.revision += 1
        // Checks finite sums and global identity uniqueness, including deleted pages.
        try DocumentCodec.validate(result)
        return result
    }

    private static func selectedPage(_ ids: Set<UUID>, pageID: UUID, revision: Int64,
                                     document: NoteDocument) throws -> Int {
        try DocumentCodec.validate(document)
        guard document.revision == revision else { throw DocumentError.staleRevision }
        guard let index = document.pages.firstIndex(where: { $0.id == pageID }),
              ids.isSubset(of: Set(document.pages[index].strokes.map(\.id))) else {
            throw DocumentError.invalidDocument("선택 획 또는 페이지")
        }
        return index
    }

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
