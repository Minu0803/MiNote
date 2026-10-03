import Foundation
import XCTest
@testable import MiNoteCore

final class PageCommandsTests: XCTestCase {
    func testDuplicateAllocatesNewIDsAndPreservesInkValues() throws {
        var original = NoteDocument.blank()
        original.pages[0].strokes = [fixtureStroke(), fixtureStroke()]
        original.pages[0].paper = .grid; original.pages[0].isBookmarked = true
        let result = try PageCommands.apply(.duplicate(original.pages[0].id), to: original)
        XCTAssertEqual(result.revision, 1); XCTAssertEqual(result.pages.count, 2)
        XCTAssertEqual(result.pages[0], original.pages[0]); XCTAssertEqual(original.pages.count, 1)
        let copy = result.pages[1]
        XCTAssertNotEqual(copy.id, original.pages[0].id); XCTAssertEqual(copy.paper, .grid)
        XCTAssertFalse(copy.isBookmarked); XCTAssertEqual(result.lastOpenedPageID, copy.id)
        for (a, b) in zip(original.pages[0].strokes, copy.strokes) {
            XCTAssertNotEqual(a.id, b.id)
            var matched = b; matched.id = a.id; XCTAssertEqual(matched, a)
        }
    }

    func testMoveDeleteRestoreKeepSelectionAndAllData() throws {
        let pages = [NotePage(strokes: [fixtureStroke()]), NotePage(paper: .ruled, isBookmarked: true), NotePage()]
        let original = NoteDocument(title: "pages", pages: pages, lastOpenedPageID: pages[1].id)
        let moved = try PageCommands.apply(.move(pages[0].id, toIndex: 2), to: original)
        XCTAssertEqual(moved.pages.map(\.id), [pages[1].id, pages[2].id, pages[0].id])
        XCTAssertEqual(moved.lastOpenedPageID, pages[1].id)
        let deleted = try PageCommands.apply(.delete(pages[1].id), to: moved)
        XCTAssertEqual(deleted.lastOpenedPageID, pages[2].id)
        XCTAssertEqual(deleted.deletedPages[0].page, pages[1]); XCTAssertEqual(deleted.deletedPages[0].originalIndex, 0)
        let restored = try PageCommands.apply(.restore(pages[1].id), to: deleted)
        XCTAssertEqual(restored.pages, moved.pages); XCTAssertEqual(restored.lastOpenedPageID, pages[1].id)
        XCTAssertTrue(restored.deletedPages.isEmpty); XCTAssertEqual(restored.revision, 3)
    }

    func testRestoreClampsIndexAndPreservesPDFReference() throws {
        var original = NoteDocument.blank()
        let asset = PDFAsset(originalFilename: "a.pdf", pageCount: 1, byteCount: 3)
        original.pdfAssets = [asset]
        let pdf = pdfFixturePage(assetID: asset.id)
        original.deletedPages = [DeletedPage(page: pdf, originalIndex: 12, deletedAt: 100)]
        let restored = try PageCommands.apply(.restore(pdf.id), to: original)
        XCTAssertEqual(restored.pages.last, pdf); XCTAssertEqual(restored.lastOpenedPageID, pdf.id)
        let duplicate = try PageCommands.apply(.duplicate(pdf.id), to: restored)
        XCTAssertEqual(duplicate.pages.last?.pdfSource, pdf.pdfSource)
        XCTAssertNoThrow(try DocumentCodec.encode(duplicate))
    }

    func testInsertPaperAndBookmarkPreserveSelectionAndIncrementOnce() throws {
        let original = NoteDocument.blank()
        let inserted = try PageCommands.apply(.insert(after: original.pages[0].id, paper: .ruled), to: original)
        XCTAssertEqual(inserted.pages[1].paper, .ruled); XCTAssertEqual(inserted.lastOpenedPageID, inserted.pages[1].id)
        let grid = try PageCommands.apply(.setPaper(original.pages[0].id, .grid), to: inserted)
        let marked = try PageCommands.apply(.setBookmark(original.pages[0].id, true), to: grid)
        XCTAssertEqual(marked.lastOpenedPageID, inserted.lastOpenedPageID)
        XCTAssertTrue(marked.pages[0].isBookmarked); XCTAssertEqual(marked.revision, 3)
    }

    func testInvalidCommandCannotMutateOrExceedLimits() throws {
        let original = NoteDocument.blank(), id = original.pages[0].id
        let commands: [PageCommand] = [.delete(id), .delete(UUID()), .duplicate(UUID()), .restore(id),
            .move(id, toIndex: -1), .move(id, toIndex: 1), .insert(after: UUID(), paper: .blank),
            .setPaper(UUID(), .grid), .setBookmark(UUID(), true)]
        for command in commands { XCTAssertThrowsError(try PageCommands.apply(command, to: original)) }
        XCTAssertEqual(original.revision, 0); XCTAssertEqual(original.pages.count, 1)
        var full = original; full.pages += (1..<1_000).map { _ in NotePage() }
        XCTAssertThrowsError(try PageCommands.apply(.insert(after: id, paper: .blank), to: full))
        XCTAssertThrowsError(try PageCommands.apply(.duplicate(id), to: full))
        var overflow = original; overflow.revision = Int64.max
        XCTAssertThrowsError(try PageCommands.apply(.setBookmark(id, true), to: overflow))
        let asset = PDFAsset(originalFilename: "a.pdf", pageCount: 1, byteCount: 3)
        let pdf = NoteDocument(title: "pdf", pages: [pdfFixturePage(assetID: asset.id)], pdfAssets: [asset])
        XCTAssertThrowsError(try PageCommands.apply(.setPaper(pdf.pages[0].id, .ruled), to: pdf))
    }
}
