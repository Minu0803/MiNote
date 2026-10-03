import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class MultiPDFStoreTests: XCTestCase {
    func testTwoPDFsWithSameFilenameKeepIndependentAssets() async throws {
        let root = try LibraryTestSupport.directory(self), store = DocumentStore(directory: root)
        var note = NoteDocument.blank(); note.pages[0].strokes = [fixtureStroke()]; try await store.save(note)
        let a = Data("PDF A".utf8), b = Data("PDF B other bytes".utf8)
        let assetA = PDFAsset(originalFilename: "same.pdf", pageCount: 1, byteCount: a.count)
        let assetB = PDFAsset(originalFilename: "same.pdf", pageCount: 1, byteCount: b.count)
        let first = try await store.attachPDF(data: a, asset: assetA, pages: [pdfFixturePage(assetID: assetA.id)],
            afterPageID: note.pages[0].id, expectedRevision: 0)
        let second = try await store.attachPDF(data: b, asset: assetB, pages: [pdfFixturePage(assetID: assetB.id)],
            afterPageID: note.pages[0].id, expectedRevision: 1)
        XCTAssertEqual(second.pages[0], note.pages[0]); XCTAssertEqual(second.pages[2], first.pages[1])
        XCTAssertEqual(second.pages[1].pdfSource?.assetID, assetB.id)
        XCTAssertEqual(second.pdfAssets, [assetA, assetB]); XCTAssertEqual(second.lastOpenedPageID, second.pages[1].id)
        XCTAssertEqual(second.revision, 2)
        let reopened = try await DocumentStore(directory: root).load(); XCTAssertEqual(reopened?.document, second)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(assetA.relativePath)), a)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(assetB.relativePath)), b)
    }

    func testFailedSecondImportAndStaleRevisionKeepFirstPDFAndInk() async throws {
        let root = try LibraryTestSupport.directory(self), store = DocumentStore(directory: root)
        var original = NoteDocument.blank(); original.pages[0].strokes = [fixtureStroke()]; try await store.save(original)
        let bytes = Data("PDF A".utf8), a = PDFAsset(originalFilename: "same.pdf", pageCount: 1, byteCount: bytes.count)
        let first = try await store.attachPDF(data: bytes, asset: a, pages: [pdfFixturePage(assetID: a.id)],
            afterPageID: original.pages[0].id, expectedRevision: 0)
        let primary = root.appendingPathComponent("document.json"), backup = root.appendingPathComponent("document.backup.json")
        let before = try Data(contentsOf: primary), backupBefore = try Data(contentsOf: backup)
        let secondBytes = Data("PDF B".utf8), b = PDFAsset(originalFilename: "same.pdf", pageCount: 1, byteCount: secondBytes.count)
        do { _ = try await store.attachPDF(data: secondBytes, asset: b, pages: [pdfFixturePage(assetID: b.id)],
            afterPageID: first.pages[1].id, expectedRevision: 0); XCTFail("Stale") }
        catch { XCTAssertEqual(error as? DocumentError, .staleRevision) }
        XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(b.relativePath).path))
        let huge = PDFAsset(originalFilename: "oversize.pdf", pageCount: 1, byteCount: 100 * 1024 * 1024 + 1)
        do { _ = try await store.attachPDF(data: secondBytes, asset: huge, pages: [pdfFixturePage(assetID: huge.id)],
            afterPageID: first.pages[1].id, expectedRevision: 1); XCTFail("Limit") } catch {}
        XCTAssertEqual(try Data(contentsOf: primary), before); XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
        try FileManager.default.removeItem(at: backup); try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        do { _ = try await store.attachPDF(data: secondBytes, asset: b, pages: [pdfFixturePage(assetID: b.id)],
            afterPageID: first.pages[1].id, expectedRevision: 1); XCTFail("JSON I/O") } catch {}
        XCTAssertEqual(try Data(contentsOf: primary), before)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(a.relativePath)), bytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(b.relativePath)), secondBytes, "Unreferenced asset is retained")
        let loaded = try await store.load(); XCTAssertEqual(loaded?.document, first)
    }

    func testIncompleteAttachmentAndAssetIDReuseCannotChangeDocument() async throws {
        let root = try LibraryTestSupport.directory(self), store = DocumentStore(directory: root)
        let original = NoteDocument.blank(); try await store.save(original)
        let bytes = Data("PDF".utf8), asset = PDFAsset(originalFilename: "a.pdf", pageCount: 2, byteCount: bytes.count)
        do { _ = try await store.attachPDF(data: bytes, asset: asset, pages: [pdfFixturePage(assetID: asset.id)],
            afterPageID: original.pages[0].id, expectedRevision: 0); XCTFail("Incomplete original mapping") } catch {}
        let loaded = try await store.load(); XCTAssertEqual(loaded?.document, original)
    }
}
