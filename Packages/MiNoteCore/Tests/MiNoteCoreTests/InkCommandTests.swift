import Foundation
import XCTest
@testable import MiNoteCore

final class InkCommandTests: XCTestCase {
    private func fixture() -> NoteDocument {
        let asset = PDFAsset(originalFilename: "source.pdf", pageCount: 1, byteCount: 3)
        var stroke = fixtureStroke()
        stroke.transform = InkTransform(a: 0, b: 1, c: -1, d: 0, tx: 10, ty: 20)
        let first = NotePage(strokes: [stroke, fixtureStroke()], paper: .grid, isBookmarked: true)
        return NoteDocument(revision: 7, title: "preserve", pages: [first, pdfFixturePage(assetID: asset.id)],
            pdfAssets: [asset], deletedPages: [DeletedPage(page: NotePage(strokes: [fixtureStroke()]), originalIndex: 0, deletedAt: 12)], lastOpenedPageID: first.id)
    }
    private func fourStrokes() -> NoteDocument {
        var doc = fixture()
        var same = doc.pages[0].strokes[0]; same.id = UUID()
        doc.pages[0].strokes += [same, fixtureStroke()]
        return doc
    }
    func testDeletePreservesRemainingOrderAndEntireOtherMetadata() throws {
        let original = fourStrokes(), page = original.pages[0]
        let next = try InkCommands.delete(strokeIDs: [page.strokes[0].id, page.strokes[2].id],
            pageID: page.id, expectedRevision: 7, in: original)
        XCTAssertEqual(next.pages[0].strokes, [page.strokes[1], page.strokes[3]])
        XCTAssertEqual(next.revision, 8)
        var restored = next; restored.pages[0].strokes = page.strokes; restored.revision = 7
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(next)), next)
    }
    func testDuplicateAppendsOrderedFreshIdentitiesAndPreservesEveryStrokeValue() throws {
        let original = fourStrokes(), page = original.pages[0]
        let next = try InkCommands.duplicate(strokeIDs: [page.strokes[2].id, page.strokes[0].id],
            pageID: page.id, dx: 20, dy: 20, expectedRevision: 7, in: original)
        let strokes = next.pages[0].strokes
        XCTAssertEqual(Array(strokes.prefix(4)), page.strokes)
        XCTAssertEqual(strokes.count, 6); XCTAssertEqual(Set(strokes.map(\.id)).count, 6)
        for (offset, source) in [page.strokes[0], page.strokes[2]].enumerated() {
            var clone = strokes[4 + offset]
            XCTAssertEqual(clone.transform, InkTransform(a: 0, b: 1, c: -1, d: 0, tx: 30, ty: 40))
            clone.id = source.id; clone.transform = source.transform
            XCTAssertEqual(clone, source)
        }
        var restored = next; restored.pages[0].strokes = page.strokes; restored.revision = 7
        XCTAssertEqual(restored, original)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(next)), next)
    }
    func testEmptySelectionAtRevisionLimitIsNoOpButStillValidatesDocument() throws {
        var doc = fourStrokes(); doc.revision = .max; let pageID = doc.pages[0].id
        XCTAssertEqual(try InkCommands.delete(strokeIDs: [], pageID: pageID, expectedRevision: .max, in: doc), doc)
        XCTAssertEqual(try InkCommands.duplicate(strokeIDs: [], pageID: pageID, dx: 20, dy: 20, expectedRevision: .max, in: doc), doc)
        doc.pages[0].strokes[0].points[0].x = .nan
        XCTAssertThrowsError(try InkCommands.delete(strokeIDs: [], pageID: pageID, expectedRevision: .max, in: doc))
        XCTAssertThrowsError(try InkCommands.duplicate(strokeIDs: [], pageID: pageID, dx: 20, dy: 20, expectedRevision: .max, in: doc))
    }
    func testSelectionCommandsRejectInvalidOwnershipRevisionsAndAmounts() throws {
        let doc = fourStrokes(), page = doc.pages[0]
        for (pageID, ids, revision) in [(UUID(), Set<UUID>(), Int64(7)),
            (page.id, Set([UUID()]), 7), (doc.pages[1].id, Set([page.strokes[0].id]), 7),
            (doc.deletedPages[0].id, Set([doc.deletedPages[0].page.strokes[0].id]), 7),
            (page.id, Set([page.strokes[0].id]), 6)] {
            XCTAssertThrowsError(try InkCommands.delete(strokeIDs: ids, pageID: pageID, expectedRevision: revision, in: doc))
            XCTAssertThrowsError(try InkCommands.duplicate(strokeIDs: ids, pageID: pageID, dx: 20, dy: 20, expectedRevision: revision, in: doc))
        }
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try InkCommands.duplicate(strokeIDs: [], pageID: page.id, dx: bad, dy: 0, expectedRevision: 7, in: doc))
            XCTAssertThrowsError(try InkCommands.duplicate(strokeIDs: [page.strokes[0].id], pageID: page.id, dx: 0, dy: bad, expectedRevision: 7, in: doc))
        }
        var huge = doc; huge.pages[0].strokes[0].transform.tx = .greatestFiniteMagnitude
        XCTAssertThrowsError(try InkCommands.duplicate(strokeIDs: [page.strokes[0].id], pageID: page.id,
            dx: .greatestFiniteMagnitude, dy: 20, expectedRevision: 7, in: huge))
        var max = doc; max.revision = .max
        XCTAssertThrowsError(try InkCommands.delete(strokeIDs: [page.strokes[0].id], pageID: page.id, expectedRevision: .max, in: max))
        XCTAssertThrowsError(try InkCommands.duplicate(strokeIDs: [page.strokes[0].id], pageID: page.id, dx: 0, dy: 0, expectedRevision: .max, in: max))
        XCTAssertEqual(doc.revision, 7); XCTAssertEqual(doc.pages[0].strokes.count, 4)
        XCTAssertEqual(huge.pages[0].strokes[0].transform.tx, .greatestFiniteMagnitude)
    }
    func testTranslationChangesOnlySelectedDocumentTransformAndOneRevision() throws {
        let original = fixture(), page = original.pages[0], stroke = page.strokes[0]
        let moved = try InkCommands.translate(strokeIDs: [stroke.id], pageID: page.id, dx: 30, dy: -15, expectedRevision: 7, in: original)
        XCTAssertEqual(moved.revision, 8)
        XCTAssertEqual(moved.pages[0].strokes[0].transform, InkTransform(a: 0, b: 1, c: -1, d: 0, tx: 40, ty: 5))
        var unchanged = moved
        unchanged.revision = 7; unchanged.pages[0].strokes[0].transform = stroke.transform
        XCTAssertEqual(unchanged, original)
        let roundtrip = try DocumentCodec.decode(DocumentCodec.encode(moved))
        XCTAssertEqual(roundtrip, moved)
        let reversed = try InkCommands.translate(strokeIDs: [stroke.id], pageID: page.id, dx: -30, dy: 15, expectedRevision: 8, in: moved)
        XCTAssertEqual(reversed.pages, original.pages); XCTAssertEqual(reversed.revision, 9)
        XCTAssertEqual(original.revision, 7)
    }
    func testStaleAndWrongPageIdentitiesCannotChangeInput() throws {
        let original = fixture(), page = original.pages[0], id = page.strokes[0].id
        XCTAssertThrowsError(try InkCommands.translate(strokeIDs: [id], pageID: page.id, dx: 2, dy: 3, expectedRevision: 6, in: original))
        for pair in [(page.id, UUID()), (original.pages[1].id, id), (original.deletedPages[0].id, original.deletedPages[0].page.strokes[0].id)] {
            XCTAssertThrowsError(try InkCommands.translate(strokeIDs: [pair.1], pageID: pair.0, dx: 2, dy: 3, expectedRevision: 7, in: original))
        }
        XCTAssertEqual(original.revision, 7); XCTAssertEqual(original.pages[0].strokes[0].transform.tx, 10)
    }
    func testNonfiniteAndOverflowTranslationFailsWithoutPartialChange() throws {
        let original = fixture(), page = original.pages[0], id = page.strokes[0].id
        for amount in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try InkCommands.translate(strokeIDs: [id], pageID: page.id, dx: amount, dy: 0, expectedRevision: 7, in: original))
            XCTAssertThrowsError(try InkCommands.translate(strokeIDs: [id], pageID: page.id, dx: 0, dy: amount, expectedRevision: 7, in: original))
        }
        var huge = original; huge.pages[0].strokes[0].transform.tx = .greatestFiniteMagnitude
        XCTAssertThrowsError(try InkCommands.translate(strokeIDs: [id], pageID: page.id, dx: .greatestFiniteMagnitude, dy: 0, expectedRevision: 7, in: huge))
        var exhausted = original; exhausted.revision = .max
        XCTAssertThrowsError(try InkCommands.translate(strokeIDs: [id], pageID: page.id, dx: 1, dy: 0, expectedRevision: .max, in: exhausted))
        XCTAssertEqual(original.pages[0].strokes[0].transform.tx, 10)
        XCTAssertEqual(huge.pages[0].strokes[0].transform.tx, .greatestFiniteMagnitude)
    }
    func testNoSelectionAndZeroDisplacementDoNotCreateAnEdit() throws {
        var original = fixture(); original.revision = .max
        let page = original.pages[0]
        XCTAssertEqual(try InkCommands.translate(strokeIDs: [], pageID: page.id, dx: 3, dy: 4, expectedRevision: .max, in: original), original)
        XCTAssertEqual(try InkCommands.translate(strokeIDs: [page.strokes[0].id], pageID: page.id, dx: 0, dy: 0, expectedRevision: .max, in: original), original)
    }
}
