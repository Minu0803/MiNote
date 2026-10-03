import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class SchemaV3Tests: XCTestCase {
    func testV1AndV2MigrateToV3WithoutIdentityOrGeometryLoss() throws {
        let rawV2 = try LibraryTestSupport.data("source")
        let migrated = try DocumentCodec.decode(rawV2)
        XCTAssertEqual(migrated.schemaVersion, 3)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: rawV2) as? [String: Any])
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentCodec.encode(migrated)) as? [String: Any])
        XCTAssertEqual(encoded["id"] as? String, raw["id"] as? String)
        XCTAssertEqual(encoded["revision"] as? Int, raw["revision"] as? Int)
        XCTAssertNotNil(encoded["pdfAssets"])
        XCTAssertNil(encoded["pdfAsset"])
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(migrated)), migrated)
        var v1 = raw
        v1["schemaVersion"] = 1; v1.removeValue(forKey: "pdfAsset")
        v1["pages"] = Array((raw["pages"] as! [[String: Any]]).prefix(1))
        let legacy = try DocumentCodec.decode(JSONSerialization.data(withJSONObject: v1))
        XCTAssertEqual(legacy.schemaVersion, 3)
        XCTAssertEqual(legacy.pages[0], migrated.pages[0])
    }

    func testLegacyInvalidMappingsAreRejectedBeforeMigration() throws {
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: LibraryTestSupport.data("source")) as? [String: Any])
        var missing = raw
        missing["pages"] = Array((raw["pages"] as! [[String: Any]]).dropLast())
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: missing)))
        var duplicate = raw
        var pages = raw["pages"] as! [[String: Any]]
        var extra = pages[1]; extra["id"] = UUID().uuidString; pages.append(extra)
        duplicate["pages"] = pages
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: duplicate)))
        var v1 = raw; v1["schemaVersion"] = 1
        XCTAssertThrowsError(try DocumentCodec.decode(JSONSerialization.data(withJSONObject: v1)))
    }
    func testDuplicatedPDFIndicesAreValidWithUniquePageAndStrokeIDs() throws {
        var document = try DocumentCodec.decode(LibraryTestSupport.data("source"))
        var copy = document.pages[1]; copy.id = UUID(); copy.strokes = [fixtureStroke()]
        document.pages.append(copy)
        XCTAssertNoThrow(try DocumentCodec.encode(document))
        XCTAssertEqual(document.pages[1].pdfSource?.assetID, document.pdfAssets[0].id)
        XCTAssertEqual(document.pages[0].paper, .blank)
        XCTAssertFalse(document.pages[0].isBookmarked)
        XCTAssertTrue(document.deletedPages.isEmpty)
        document.pages[5].pdfSource = PDFPageSource(assetID: UUID(), index: 0,
            mediaBox: copy.pdfSource!.mediaBox, cropBox: copy.pdfSource!.cropBox, rotation: 0)
        XCTAssertThrowsError(try DocumentCodec.encode(document))
        document.pages[5] = copy
        document.pages[5].strokes = document.pages[0].strokes
        XCTAssertThrowsError(try DocumentCodec.encode(document))
        document.pages[5] = copy; document.pages[5].id = document.pages[0].strokes[0].id
        XCTAssertThrowsError(try DocumentCodec.encode(document))
        document.pages[5] = copy
        document.pages[5].pdfSource = PDFPageSource(assetID: document.pdfAssets[0].id, index: 4,
            mediaBox: copy.pdfSource!.mediaBox, cropBox: copy.pdfSource!.cropBox, rotation: 0)
        XCTAssertThrowsError(try DocumentCodec.encode(document))
    }

    func testUnsupportedSchemaAndMissingSecondAssetPreservePrimaryAndBackup() async throws {
        let root = try LibraryTestSupport.directory(self), store = DocumentStore(directory: root)
        let bytes = Data("original PDF bytes".utf8)
        let assets = (0..<2).map { _ in PDFAsset(originalFilename: "same.pdf", pageCount: 1, byteCount: bytes.count) }
        var document = NoteDocument(title: "two", pages: assets.map { asset in
            var page = pdfFixturePage(); page.pdfSource = PDFPageSource(assetID: asset.id, index: 0,
                mediaBox: page.pdfSource!.mediaBox, cropBox: page.pdfSource!.cropBox, rotation: 0)
            return page
        }, pdfAssets: assets)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        for asset in assets { try bytes.write(to: root.appendingPathComponent(asset.relativePath)) }
        try await store.save(document); document.revision += 1; try await store.save(document)
        let primary = root.appendingPathComponent("document.json"), backup = root.appendingPathComponent("document.backup.json")
        let before = try Data(contentsOf: primary), backupBefore = try Data(contentsOf: backup)
        let second = root.appendingPathComponent(assets[1].relativePath)
        for damage in [Data(), bytes + Data([0])] {
            try damage.write(to: second)
            do { _ = try await store.load(); XCTFail("Must not fall back to single PDF") }
            catch { XCTAssertEqual(error as? DocumentError, .missingAsset) }
            do { try await store.save(document); XCTFail("Must preserve") } catch {}
            XCTAssertEqual(try Data(contentsOf: primary), before)
            XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
        }
        try FileManager.default.removeItem(at: second)
        do { _ = try await store.load(); XCTFail("Missing must block") }
        catch { XCTAssertEqual(error as? DocumentError, .missingAsset) }
        let future = Data(#"{"schemaVersion":99}"#.utf8); try future.write(to: primary)
        do { _ = try await store.load(); XCTFail("Future must block") }
        catch { XCTAssertEqual(error as? DocumentError, .unsupportedSchema(99)) }
        XCTAssertEqual(try Data(contentsOf: primary), future)
        XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
    }

    func testSavingMigratedV2PreservesRawBackupAndLibraryCopiesAllAssets() async throws {
        let root = try LibraryTestSupport.directory(self)
        let migrated = try LibraryTestSupport.seedLegacy(at: root)
        let raw = try Data(contentsOf: root.appendingPathComponent("document.json"))
        try await DocumentStore(directory: root).save(migrated)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.backup.json")), raw)
        var multi = migrated
        let original = multi.pdfAssets[0]
        let second = PDFAsset(originalFilename: "second.pdf", pageCount: original.pageCount, byteCount: original.byteCount)
        multi.pdfAssets.append(second); multi.revision += 1
        try Data(contentsOf: root.appendingPathComponent(original.relativePath)).write(to: root.appendingPathComponent(second.relativePath))
        try await DocumentStore(directory: root).save(multi)
        let library = LibraryStore(directory: root)
        _ = try await library.load()
        let noteRoot = root.appendingPathComponent("notes/\(multi.id.uuidString)")
        let copied = try await DocumentStore(directory: noteRoot).load()
        XCTAssertEqual(copied?.document, multi)
        for asset in multi.pdfAssets {
            XCTAssertEqual(try Data(contentsOf: noteRoot.appendingPathComponent(asset.relativePath)),
                           try Data(contentsOf: root.appendingPathComponent(asset.relativePath)))
        }
    }

}
