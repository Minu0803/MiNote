import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class LibraryMigrationTests: XCTestCase {
    func testLegacyMigrationPreservesIDsInkAssetsAndRawBackup() async throws {
        let root = try LibraryTestSupport.directory(self)
        let expected = try LibraryTestSupport.seedLegacy(at: root)
        let raw = try LibraryTestSupport.data("source")
        let store = LibraryStore(directory: root)
        let first = try await store.load()
        let second = try await LibraryStore(directory: root).load()
        XCTAssertEqual(first.catalog.notes.map(\.id), [expected.id])
        XCTAssertEqual(second.catalog, first.catalog)
        let migrated = try await store.documentStore(for: expected.id)
        let loaded = try await migrated.load()
        XCTAssertEqual(loaded?.document, expected)
        let newRoot = root.appendingPathComponent("notes/\(expected.id.uuidString)")
        XCTAssertEqual(try Data(contentsOf: newRoot.appendingPathComponent("document.backup.json")), raw)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.json")), raw)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.backup.json")), raw)
        let asset = try XCTUnwrap(expected.pdfAssets.first)
        XCTAssertEqual(try Data(contentsOf: newRoot.appendingPathComponent(asset.relativePath)), try LibraryTestSupport.data("source", extension: "pdf"))
    }

    func testV1MigrationAndCorruptPrimaryRecoveryPreserveOriginalBytes() async throws {
        for corrupt in [false, true] {
            let root = try LibraryTestSupport.directory(self)
            let note = NoteDocument(title: "기존 v1", pages: [NotePage(strokes: [fixtureStroke()])])
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentCodec.encode(note)) as? [String: Any])
            object["schemaVersion"] = 1
            let raw = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try raw.write(to: root.appendingPathComponent("document.backup.json"))
            let primary = corrupt ? Data("broken".utf8) : raw
            try primary.write(to: root.appendingPathComponent("document.json"))
            let library = LibraryStore(directory: root)
            let result = try await library.load()
            let store = try await library.documentStore(for: note.id)
            let migrated = try await store.load()
            XCTAssertEqual(migrated?.document, note)
            XCTAssertEqual(result.catalog.notes.map(\.id), [note.id])
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.json")), primary)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.backup.json")), raw)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("notes/\(note.id.uuidString)/document.backup.json")), raw)
        }
    }

    func testInvalidLegacyOrUnsupportedCatalogBlocksBlankReplacement() async throws {
        for raw in [Data("broken".utf8), Data(#"{"schemaVersion":99}"#.utf8)] {
            let root = try LibraryTestSupport.directory(self)
            let primary = root.appendingPathComponent("document.json")
            try raw.write(to: primary)
            do { _ = try await LibraryStore(directory: root).load(); XCTFail("Invalid legacy must block migration") } catch {}
            XCTAssertEqual(try Data(contentsOf: primary), raw)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("library.json").path))
        }
        let root = try LibraryTestSupport.directory(self)
        _ = try LibraryTestSupport.seedLegacy(at: root)
        let future = Data(#"{"version":99}"#.utf8)
        try future.write(to: root.appendingPathComponent("library.json"))
        let emptyBackup = try JSONEncoder().encode(LibraryCatalog())
        try emptyBackup.write(to: root.appendingPathComponent("library.backup.json"))
        do { _ = try await LibraryStore(directory: root).load(); XCTFail("Future catalog cannot fall back") }
        catch { XCTAssertEqual(error as? LibraryError, .unsupportedVersion(99)) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), future)
    }

    func testMissingLegacyAssetBlocksMigrationAndPreservesSource() async throws {
        let root = try LibraryTestSupport.directory(self)
        let doc = try LibraryTestSupport.seedLegacy(at: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(try XCTUnwrap(doc.pdfAssets.first).relativePath))
        do { _ = try await LibraryStore(directory: root).load(); XCTFail("Missing asset cannot be hidden by a blank library") }
        catch { XCTAssertEqual(error as? DocumentError, .missingAsset) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.json")), try LibraryTestSupport.data("source"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("library.json").path))
    }

    func testMigrationCatalogWriteFailureLeavesSourceAndRetryIsIdempotent() async throws {
        let root = try LibraryTestSupport.directory(self)
        let expected = try LibraryTestSupport.seedLegacy(at: root)
        let broken = LibraryStore(directory: root, catalogWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        do { _ = try await broken.load(); XCTFail("Catalog write failure must be reported") } catch {}
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("document.json")), try LibraryTestSupport.data("source"))
        let retry = LibraryStore(directory: root)
        let result = try await retry.load()
        XCTAssertEqual(result.catalog.notes.map(\.id), [expected.id])
        let again = try await retry.load()
        XCTAssertEqual(again.catalog.notes.count, 1)
    }
}
