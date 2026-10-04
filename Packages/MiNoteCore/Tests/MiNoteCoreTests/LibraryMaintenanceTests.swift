import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class LibraryMaintenanceTests: XCTestCase {
    func testOnlyKnownUnreferencedAssetsAreCandidates() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root)
        _ = try await library.load(); let id = try await library.createNote(title: "N")
        let store = try await library.documentStore(for: id), directory = root.appendingPathComponent("notes/\(id)")
        let data = Data("PDF bytes".utf8), asset = PDFAsset(originalFilename: "A.pdf", pageCount: 1, byteCount: data.count)
        let original = try await store.load(), blank = try XCTUnwrap(original?.document.pages[0].id)
        let attached = try await store.attachPDF(data: data, asset: asset, pages: [pdfFixturePage(assetID: asset.id)], afterPageID: blank, expectedRevision: 0)
        let removed = try await store.applyPageCommand(.delete(attached.pages[1].id), expectedRevision: attached.revision)
        let orphan = directory.appendingPathComponent("assets/\(UUID()).pdf"), unknown = directory.appendingPathComponent("assets/keep.txt")
        try data.write(to: orphan); try data.write(to: unknown)
        let legacy = root.appendingPathComponent("document.json"); try Data("keep legacy".utf8).write(to: legacy)
        let report = try await library.maintenanceReport()
        XCTAssertEqual(report.candidates.map { $0.url.resolvingSymlinksInPath() }, [orphan.resolvingSymlinksInPath()])
        _ = try await library.cleanUnreferencedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        let assetURL = directory.appendingPathComponent(asset.relativePath)
        XCTAssertEqual(try Data(contentsOf: assetURL), data)
        let purged = try await library.purgeDeletedPages([removed.deletedPages[0].id], noteID: id, expectedRevision: removed.revision)
        XCTAssertTrue(purged.pdfAssets.isEmpty); XCTAssertTrue(purged.deletedPages.isEmpty)
        let protected = try await library.maintenanceReport()
        XCTAssertTrue(protected.candidates.isEmpty) // Previous document still owns it.
        var latest = purged; latest.revision += 1; latest.pages[0].isBookmarked = true; latest.pages[0].strokes = [fixtureStroke()]; try await store.save(latest)
        let final = try await library.maintenanceReport()
        XCTAssertEqual(final.candidates.map { $0.url.resolvingSymlinksInPath() }, [assetURL.resolvingSymlinksInPath()])
        _ = try await library.cleanUnreferencedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: assetURL.path))
        let reopened = try await store.load(); XCTAssertEqual(reopened?.document, latest)
    }
    func testUnusableSnapshotBlocksCleanupAndInvalidPagePurgePreservesBytes() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root)
        _ = try await library.load(); let id = try await library.createNote(title: "N"), store = try await library.documentStore(for: id)
        let directory = root.appendingPathComponent("notes/\(id)"), json = directory.appendingPathComponent("document.json")
        let before = try Data(contentsOf: json), loaded = try await store.load(), page = try XCTUnwrap(loaded?.document.pages[0].id)
        for (ids, revision) in [([page], Int64(0)), ([UUID()], 0), ([page], 9)] {
            do { _ = try await library.purgeDeletedPages(ids, noteID: id, expectedRevision: revision); XCTFail("invalid purge") } catch { }
        }
        XCTAssertEqual(try Data(contentsOf: json), before)
        let assets = directory.appendingPathComponent("assets"); try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let orphan = assets.appendingPathComponent("\(UUID()).pdf"); try Data("orphan".utf8).write(to: orphan)
        for raw in [Data("corrupt".utf8), Data("{\"schemaVersion\":4}".utf8)] {
            try raw.write(to: directory.appendingPathComponent("document.backup.json"))
            let result = try await library.cleanUnreferencedFiles()
            XCTAssertTrue(result.candidates.isEmpty); XCTAssertFalse(result.protectedItems.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        }
    }
}
