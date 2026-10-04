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
