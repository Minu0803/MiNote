import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class LibraryMutationTests: XCTestCase {
    func testTwoNotesKeepIndependentPDFAndRevision() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root)
        _ = try await library.load()
        let a = try await library.createNote(title: "A"), b = try await library.createNote(title: "B")
        let storeA = try await library.documentStore(for: a), storeB = try await library.documentStore(for: b)
        let sameA = try await library.documentStore(for: a)
        XCTAssertTrue(storeA === sameA)
        let loadedA = try await storeA.load()
        var note = try XCTUnwrap(loadedA?.document)
        note.pages[0].strokes = [fixtureStroke()]; note.revision += 1
        try await storeA.save(note)
        let bytes = Data("PDF A".utf8), asset = PDFAsset(originalFilename: "A.pdf", pageCount: 1, byteCount: bytes.count)
        let imported = try await storeA.attachPDF(data: bytes, asset: asset, pages: [pdfFixturePage(assetID: asset.id)], afterPageID: note.pages[0].id, expectedRevision: 1)
        let reopened = LibraryStore(directory: root); _ = try await reopened.load()
        let restoredStore = try await reopened.documentStore(for: a)
        let restored = try await restoredStore.load(), other = try await storeB.load()
        XCTAssertEqual(restored?.document, imported)
        XCTAssertEqual(other?.document.title, "B"); XCTAssertEqual(other?.document.revision, 0)
        XCTAssertEqual(other?.document.pages[0].strokes, []); XCTAssertNil(other?.document.pdfAsset)
        let path = try await restoredStore.assetURL(for: asset)
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testRenameReadsLatestDocumentAndDoesNotDiscardInk() async throws {
        let library = LibraryStore(directory: try LibraryTestSupport.directory(self)); _ = try await library.load()
        let id = try await library.createNote(title: "before")
        let store = try await library.documentStore(for: id)
        let loaded = try await store.load()
        var latest = try XCTUnwrap(loaded?.document)
        latest.revision = 7; latest.pages[0].strokes = [fixtureStroke()]; try await store.save(latest)
        try await library.renameNote(id: id, title: " after ")
        let result = try await store.load()
        latest.title = "after"; latest.revision += 1
        XCTAssertEqual(result?.document, latest)
    }

    func testMoveFolderRejectsCyclesAndMissingParent() async throws {
        let library = LibraryStore(directory: try LibraryTestSupport.directory(self)); _ = try await library.load()
        let a = try await library.createFolder(name: "A"), b = try await library.createFolder(name: "B", parentID: a)
        let before = try await library.load().catalog
        do { try await library.moveFolder(id: a, parentID: b); XCTFail("Cycle") } catch {}
        do { try await library.moveFolder(id: b, parentID: UUID()); XCTFail("Missing parent") } catch {}
        let after = try await library.load().catalog
        XCTAssertEqual(after, before)
    }

    func testFolderRenameDoesNotChangeIDsOrMembership() async throws {
        let library = LibraryStore(directory: try LibraryTestSupport.directory(self)); _ = try await library.load()
        let folder = try await library.createFolder(name: " same "), duplicate = try await library.createFolder(name: "same")
        let id = try await library.createNote(title: "N", folderID: folder)
        try await library.renameFolder(id: folder, name: " work ")
        let result = try await library.load().catalog
        XCTAssertEqual(result.folders.map(\.id), [folder, duplicate]); XCTAssertEqual(result.folders[0].name, "work")
        XCTAssertEqual(result.notes.first?.folderID, folder)
        do { try await library.renameFolder(id: folder, name: " \n "); XCTFail("Empty name") } catch {}
        do { _ = try await library.createNote(title: " "); XCTFail("Empty title") } catch {}
        do { try await library.moveNote(id: id, folderID: UUID()); XCTFail("Missing folder") } catch {}
        try await library.moveNote(id: id, folderID: nil)
        let moved = try await library.load().catalog
        XCTAssertNil(moved.notes.first?.folderID)
    }

    func testTrashAndRestorePreserveNoteAndFolder() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root); _ = try await library.load()
        let folder = try await library.createFolder(name: "Work"), id = try await library.createNote(title: "N", folderID: folder)
        let store = try await library.documentStore(for: id), doc = try await store.load()?.document
        let raw = try Data(contentsOf: root.appendingPathComponent("notes/\(id.uuidString)/document.json"))
        try await library.trashNote(id: id)
        let trash = try await library.load().catalog
        XCTAssertNotNil(trash.notes.first?.trashedAt); XCTAssertEqual(trash.notes.first?.folderID, folder)
        try await library.restoreNote(id: id)
        let restored = try await library.load().catalog, reopened = try await store.load()
        XCTAssertNil(restored.notes.first?.trashedAt); XCTAssertEqual(restored.notes.first?.folderID, folder)
        XCTAssertEqual(reopened?.document, doc)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("notes/\(id.uuidString)/document.json")), raw)
    }

    func testCatalogWriteFailureRetainsLastGoodState() async throws {
        let root = try LibraryTestSupport.directory(self), library = LibraryStore(directory: root); _ = try await library.load()
        let id = try await library.createNote(title: "A")
        let before = try await library.load().catalog
        let broken = LibraryStore(directory: root, catalogWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        _ = try await broken.load()
        do { try await broken.trashNote(id: id); XCTFail("Disk failure") } catch {}
        let after = try await library.load().catalog
        XCTAssertEqual(after, before)
        do { _ = try await broken.createNote(title: "recover me"); XCTFail("Catalog failure") } catch {}
        let recovered = try await library.load()
        XCTAssertEqual(recovered.catalog.notes.count, 2); XCTAssertEqual(recovered.recoveredNoteIDs.count, 1)
    }

    func testConcurrentMutationIsRejectedBeforeSecondCommit() async throws {
        let library = LibraryStore(directory: try LibraryTestSupport.directory(self)); _ = try await library.load()
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<10 { group.addTask { do { _ = try await library.createNote(title: "N\(index)"); return true } catch { return false } } }
            var results = [Bool](); for await result in group { results.append(result) }; return results
        }
        XCTAssertTrue(outcomes.contains(false))
        let result = try await library.load().catalog
        XCTAssertEqual(result.notes.count, outcomes.filter { $0 }.count)
        XCTAssertEqual(result.revision, Int64(result.notes.count))
    }

    func testStaleCatalogActorCannotOverwriteAnotherMutation() async throws {
        let root = try LibraryTestSupport.directory(self), first = LibraryStore(directory: root), second = LibraryStore(directory: root)
        _ = try await first.load(); _ = try await second.load()
        let folder = try await first.createFolder(name: "new")
        do { _ = try await second.createFolder(name: "stale"); XCTFail("Stale actor") }
        catch { XCTAssertEqual(error as? LibraryError, .conflict) }
        let result = try await second.load().catalog
        XCTAssertEqual(result.folders.map(\.id), [folder])
    }
}
