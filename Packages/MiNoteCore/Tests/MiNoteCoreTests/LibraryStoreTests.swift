import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class LibraryStoreTests: XCTestCase {
    func testFreshLibraryIsEmptyAndDoesNotCreateAnUnrequestedNote() async throws {
        let root = try LibraryTestSupport.directory(self)
        let result = try await LibraryStore(directory: root).load()
        XCTAssertEqual(result.catalog.notes, [])
        XCTAssertEqual(result.catalog.folders, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("document.json").path))
    }

    func testInterruptedCreationExposesUnlinkedNoteForRecovery() async throws {
        let root = try LibraryTestSupport.directory(self)
        _ = try await LibraryStore(directory: root).load()
        let note = NoteDocument.blank()
        let directory = root.appendingPathComponent("notes/\(note.id.uuidString)")
        try await DocumentStore(directory: directory).save(note)
        let result = try await LibraryStore(directory: root).load()
        XCTAssertEqual(result.catalog.notes.map(\.id), [note.id])
        XCTAssertEqual(result.recoveredNoteIDs, [note.id])
        XCTAssertNotNil(result.recoveryNotice)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("document.json")), try DocumentCodec.encode(note))
    }

    func testMissingNoteIsListedButNeverReplacedByBlankEditor() async throws {
        let root = try LibraryTestSupport.directory(self)
        let note = NoteDocument.blank()
        let orphan = root.appendingPathComponent("notes/\(note.id.uuidString)")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let library = LibraryStore(directory: root)
        let result = try await library.load()
        XCTAssertEqual(result.catalog.notes.map(\.id), [note.id])
        do { _ = try await library.documentStore(for: note.id); XCTFail("Missing document must not create blank contents") }
        catch { XCTAssertEqual(error as? LibraryError, .documentMissing(note.id)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.appendingPathComponent("document.json").path))
    }

    func testCorruptCatalogRecoversOnlyFromGoodBackupAndKeepsBackupBytes() async throws {
        let root = try LibraryTestSupport.directory(self)
        let expected = LibraryCatalog()
        let raw = try JSONEncoder().encode(expected)
        try raw.write(to: root.appendingPathComponent("library.backup.json"))
        try Data("broken".utf8).write(to: root.appendingPathComponent("library.json"))
        let result = try await LibraryStore(directory: root).load()
        XCTAssertEqual(result.catalog, expected)
        XCTAssertNotNil(result.recoveryNotice)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.backup.json")), raw)
    }

    func testCatalogDirectoryOrCorruptWithoutBackupIsNotOverwritten() async throws {
        for isDirectory in [false, true] {
            let root = try LibraryTestSupport.directory(self)
            let primary = root.appendingPathComponent("library.json")
            if isDirectory { try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: false) }
            else { try Data("broken".utf8).write(to: primary) }
            do { _ = try await LibraryStore(directory: root).load(); XCTFail("Unreadable catalog is not an empty library") } catch {}
            if !isDirectory { XCTAssertEqual(try Data(contentsOf: primary), Data("broken".utf8)) }
            else { var directory: ObjCBool = false; XCTAssertTrue(FileManager.default.fileExists(atPath: primary.path, isDirectory: &directory)); XCTAssertTrue(directory.boolValue) }
        }
    }
}
