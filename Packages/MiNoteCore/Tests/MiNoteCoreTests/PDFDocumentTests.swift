import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class PDFDocumentTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAttachPersistsAssetBeforeDocumentAndKeepsOriginalInk() async throws {
        let url = try directory()
        let store = DocumentStore(directory: url)
        var original = NoteDocument.blank()
        original.pages[0].strokes = [fixtureStroke()]
        try await store.save(original)
        let bytes = Data("immutable PDF bytes".utf8)
        let asset = PDFAsset(originalFilename: "lesson.pdf", pageCount: 1, byteCount: bytes.count)
        let page = pdfFixturePage(assetID: asset.id)
        let imported = try await store.attachPDF(data: bytes, asset: asset, pages: [page], expectedRevision: 0)
        XCTAssertEqual(imported.id, original.id)
        XCTAssertEqual(imported.pages[0], original.pages[0])
        XCTAssertEqual(imported.pages[1], page)
        XCTAssertEqual(imported.revision, 1)
        let reopened = try await DocumentStore(directory: url).load()
        XCTAssertEqual(reopened?.document, imported)
        let assetURL = try await store.assetURL(for: asset)
        XCTAssertEqual(try Data(contentsOf: assetURL), bytes)
        let backup = try DocumentCodec.decode(Data(contentsOf: url.appendingPathComponent("document.backup.json")))
        XCTAssertEqual(backup, original)
    }

    func testFailedImportPreservesCurrentDocumentAndRetrySucceeds() async throws {
        let url = try directory()
        let store = DocumentStore(directory: url)
        let original = NoteDocument.blank()
        try await store.save(original)
        let before = try Data(contentsOf: url.appendingPathComponent("document.json"))
        let backup = url.appendingPathComponent("document.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        let bytes = Data("PDF".utf8)
        let asset = PDFAsset(originalFilename: "test.pdf", pageCount: 1, byteCount: bytes.count)
        do { _ = try await store.attachPDF(data: bytes, asset: asset, pages: [pdfFixturePage()], expectedRevision: 0); XCTFail("Must fail") } catch {}
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("document.json")), before)
        try FileManager.default.removeItem(at: backup)
        let imported = try await store.attachPDF(data: bytes, asset: asset, pages: [pdfFixturePage()], expectedRevision: 0)
        XCTAssertEqual(imported.pages.count, 2)
    }

    func testOutdatedImportCannotOverwriteAnEdit() async throws {
        let url = try directory()
        let store = DocumentStore(directory: url)
        var original = NoteDocument.blank()
        try await store.save(original)
        original.revision = 1
        original.pages[0].strokes = [fixtureStroke()]
        try await store.save(original)
        let bytes = Data("PDF".utf8)
        do {
            _ = try await store.attachPDF(data: bytes, asset: PDFAsset(originalFilename: "test.pdf", pageCount: 1, byteCount: bytes.count), pages: [pdfFixturePage()], expectedRevision: 0)
            XCTFail("Must reject stale import")
        } catch { XCTAssertEqual(error as? DocumentError, .staleRevision) }
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.document, original)
    }

    func testMissingAssetCannotRecoverToOlderBlankOrOverwriteInk() async throws {
        let url = try directory()
        let store = DocumentStore(directory: url)
        try await store.save(.blank())
        let bytes = Data("PDF".utf8)
        let asset = PDFAsset(originalFilename: "test.pdf", pageCount: 1, byteCount: bytes.count)
        let imported = try await store.attachPDF(data: bytes, asset: asset, pages: [pdfFixturePage()], expectedRevision: 0)
        let assetURL = try await store.assetURL(for: asset)
        try FileManager.default.removeItem(at: assetURL)
        let before = try Data(contentsOf: url.appendingPathComponent("document.json"))
        do { _ = try await store.load(); XCTFail("Must block missing original") }
        catch { XCTAssertEqual(error as? DocumentError, .missingAsset) }
        do { try await store.save(imported); XCTFail("Must not overwrite") } catch {}
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("document.json")), before)
    }

    func testRepeatedPDFPageMappingAndWrongDimensionsAreValidated() throws {
        let bytes = Data("PDF".utf8)
        var document = NoteDocument.blank()
        document.pdfAsset = PDFAsset(originalFilename: "test.pdf", pageCount: 1, byteCount: bytes.count)
        document.pages.append(pdfFixturePage(assetID: document.pdfAssets[0].id))
        XCTAssertNoThrow(try DocumentCodec.encode(document))
        document.pages[1].width = 500
        XCTAssertThrowsError(try DocumentCodec.encode(document))
        document.pages[1] = pdfFixturePage(assetID: document.pdfAssets[0].id)
        document.pages.append(pdfFixturePage(assetID: document.pdfAssets[0].id))
        XCTAssertNoThrow(try DocumentCodec.encode(document))
    }

    func testSavingMigratedDocumentKeepsRawV1Backup() async throws {
        let url = try directory()
        let original = NoteDocument.blank()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentCodec.encode(original)) as? [String: Any])
        json["schemaVersion"] = 1
        let old = try JSONSerialization.data(withJSONObject: json)
        try old.write(to: url.appendingPathComponent("document.json"))
        let store = DocumentStore(directory: url)
        let result = try await store.load()
        let migrated = try XCTUnwrap(result?.document)
        try await store.save(migrated)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("document.backup.json")), old)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("document.json"))) as? [String: Any])
        XCTAssertEqual(saved["schemaVersion"] as? Int, 3)
    }
}

func pdfFixturePage(assetID: UUID? = nil) -> NotePage {
    NotePage(width: 300, height: 450, pdfSource: PDFPageSource(assetID: assetID, index: 0,
        mediaBox: PageRect(x: 10, y: 20, width: 400, height: 600),
        cropBox: PageRect(x: 40, y: 70, width: 300, height: 450), rotation: 0))
}
