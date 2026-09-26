import Foundation
import XCTest
@testable import MiNoteCore

@MainActor
final class DocumentStoreTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSaveReloadAndPreviousVersionBackup() async throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        let empty = try await store.load()
        XCTAssertNil(empty)
        var document = NoteDocument.blank()
        try await store.save(document)
        let first = document
        document.revision = 1
        document.pages[0].strokes = [fixtureStroke()]
        try await store.save(document)
        let loaded = try await DocumentStore(directory: directory).load()
        XCTAssertEqual(loaded?.document, document)
        XCTAssertEqual(loaded?.recoveredFromBackup, false)
        let backup = try DocumentCodec.decode(Data(contentsOf: directory.appendingPathComponent("document.backup.json")))
        XCTAssertEqual(backup, first)
    }

    func testNewestRevisionWinsConcurrentSaves() async throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        let original = NoteDocument.blank()
        await withTaskGroup(of: Void.self) { group in
            for revision in 0..<30 {
                var document = original
                document.revision = Int64(revision)
                group.addTask { _ = try? await store.save(document) }
            }
        }
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.document.revision, 29)
        do { try await store.save(original); XCTFail("Must reject stale revision") }
        catch { XCTAssertEqual(error as? DocumentError, .staleRevision) }
    }

    func testSameRevisionWithDifferentContentCannotOverwrite() async throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        var document = NoteDocument.blank()
        try await store.save(document)
        document.title = "different"
        do { try await store.save(document); XCTFail("Must reject conflict") }
        catch { XCTAssertEqual(error as? DocumentError, .documentConflict) }
    }

    func testCorruptPrimaryRecoversAndKeepsGoodBackupDuringRepair() async throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        var document = NoteDocument.blank()
        document.pages[0].strokes = [fixtureStroke()]
        try await store.save(document)
        let previous = document
        document.revision = 1
        try await store.save(document)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("document.json"))
        let reopened = DocumentStore(directory: directory)
        let recovered = try await reopened.load()
        XCTAssertEqual(recovered?.document, previous)
        XCTAssertEqual(recovered?.recoveredFromBackup, true)
        var repaired = try XCTUnwrap(recovered?.document)
        repaired.revision += 1
        try await reopened.save(repaired)
        let backup = try DocumentCodec.decode(Data(contentsOf: directory.appendingPathComponent("document.backup.json")))
        XCTAssertEqual(backup, previous)
        let final = try await reopened.load()
        XCTAssertEqual(final?.document, repaired)
        XCTAssertEqual(final?.recoveredFromBackup, false)
    }

    func testPrimaryReadFailureDoesNotRecoverFromBackupOrOverwriteIt() async throws {
        let directory = try temporaryDirectory()
        let document = NoteDocument.blank()
        let backup = directory.appendingPathComponent("document.backup.json")
        let primary = directory.appendingPathComponent("document.json")
        let backupData = try DocumentCodec.encode(document)
        try backupData.write(to: backup)
        try backupData.write(to: primary)
        let store = DocumentStore(directory: directory) { url in
            if url.lastPathComponent == "document.json" {
                throw CocoaError(.fileReadNoPermission)
            }
            return try Data(contentsOf: url)
        }

        do { _ = try await store.load(); XCTFail("An I/O error must not be mistaken for corrupt JSON") }
        catch { XCTAssertFalse(error is DocumentError) }
        do { try await store.save(.blank()); XCTFail("An unreadable primary must not be replaced") }
        catch { XCTAssertFalse(error is DocumentError) }
        XCTAssertEqual(try Data(contentsOf: backup), backupData)
        XCTAssertEqual(try Data(contentsOf: primary), backupData)
    }

    func testNonFilePrimaryDoesNotRecoverFromBackupOrOverwriteIt() async throws {
        let directory = try temporaryDirectory()
        let document = NoteDocument.blank()
        let backup = directory.appendingPathComponent("document.backup.json")
        let primary = directory.appendingPathComponent("document.json")
        let backupData = try DocumentCodec.encode(document)
        try backupData.write(to: backup)
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: false)
        let store = DocumentStore(directory: directory)

        do { _ = try await store.load(); XCTFail("A directory cannot stand in for a readable document") }
        catch { XCTAssertTrue(error is POSIXError) }
        do { try await store.save(.blank()); XCTFail("A directory primary must not be replaced") }
        catch { XCTAssertTrue(error is POSIXError) }
        XCTAssertEqual(try Data(contentsOf: backup), backupData)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCorruptDocumentWithoutBackupIsNeverOverwritten() async throws {
        let directory = try temporaryDirectory()
        let primary = directory.appendingPathComponent("document.json")
        let broken = Data("broken".utf8)
        try broken.write(to: primary)
        let store = DocumentStore(directory: directory)
        do { _ = try await store.load(); XCTFail("Must report corruption") } catch {}
        do { try await store.save(.blank()); XCTFail("Must not replace corrupt document") } catch {}
        XCTAssertEqual(try Data(contentsOf: primary), broken)
    }

    func testFutureSchemaDoesNotFallBackToOlderBackupOrOverwrite() async throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        var document = NoteDocument.blank()
        try await store.save(document)
        document.revision = 1
        try await store.save(document)
        let future = Data(#"{"schemaVersion":99}"#.utf8)
        let primary = directory.appendingPathComponent("document.json")
        try future.write(to: primary)
        do { _ = try await store.load(); XCTFail("Must reject future schema") }
        catch { XCTAssertEqual(error as? DocumentError, .unsupportedSchema(99)) }
        do { try await store.save(document); XCTFail("Must preserve future document") } catch {}
        XCTAssertEqual(try Data(contentsOf: primary), future)
    }

    func testBackupWriteFailureLeavesPrimaryIntactAndRetryWorks() async throws {
        let directory = try temporaryDirectory()
        let store = DocumentStore(directory: directory)
        var document = NoteDocument.blank()
        try await store.save(document)
        let original = try Data(contentsOf: directory.appendingPathComponent("document.json"))
        let backup = directory.appendingPathComponent("document.backup.json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        document.revision = 1
        do { try await store.save(document); XCTFail("Must report failed write") } catch {}
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("document.json")), original)
        try FileManager.default.removeItem(at: backup)
        try await store.save(document)
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.document, document)
    }

    func testMissingPrimaryUsesBackupRatherThanNewBlankDocument() async throws {
        let directory = try temporaryDirectory()
        let expected = NoteDocument.blank()
        try DocumentCodec.encode(expected).write(to: directory.appendingPathComponent("document.backup.json"))
        let loaded = try await DocumentStore(directory: directory).load()
        XCTAssertEqual(loaded?.document, expected)
        XCTAssertEqual(loaded?.recoveredFromBackup, true)
    }
}
