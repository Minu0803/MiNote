import MiNoteCore
import PencilKit
import XCTest
@testable import MiNote
@testable import MiNoteCore

@MainActor final class BackupSessionTests: XCTestCase {
    func testBackupFlushesLatestDrawingAndRestoresAsEditableNewNote() async throws {
        let root = try directory(), registry = ExportFileRegistry(root: root.appendingPathComponent("exports"))
        let editor = EditorSession(store: DocumentStore(directory: root.appendingPathComponent("source")), exportRegistry: registry)
        await editor.loadIfNeeded(); editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
        let exported = await editor.exportBackup(), file = try XCTUnwrap(exported)
        let expected = try XCTUnwrap(editor.document)
        let prepared = try await BackupFileAccess().prepare(url: file.url)
        defer { try? FileManager.default.removeItem(at: prepared.stagingDirectory) }
        XCTAssertEqual(prepared.document, expected)
        let store = LibraryStore(directory: root.appendingPathComponent("library")), library = LibrarySession(store: store, exportRegistry: registry)
        await library.load(); await library.restoreBackup(from: file.url, folderID: nil)
        XCTAssertEqual(library.notes.count, 1); XCTAssertNil(library.operationError)
        await library.openNote(try XCTUnwrap(library.notes.first?.id))
        XCTAssertEqual(library.selectedEditor?.strokeCount, 1)
        library.selectedEditor?.receiveDrawing(PKDrawing(strokes: [sampleStroke(), sampleStroke(offset: 50)]))
        let closed = await library.closeNote(); XCTAssertTrue(closed)
        await library.restoreBackup(from: file.url, folderID: nil)
        XCTAssertEqual(Set(library.notes.map(\.id)).count, 2)
        try await registry.release(file.lease)
    }
    func testLateSupportedOrUnsupportedDrawingBlocksBackupAndKeepsVisibleInk() async throws {
        for unsupported in [false, true] {
            let root = try directory(), delivery = BackupLateDrawing(), gate = BackupReadGate()
            delivery.unsupported = unsupported
            let store = DocumentStore(directory: root.appendingPathComponent("source"), dataReader: { url in
                let bytes = try Data(contentsOf: url)
                if gate.fire() {
                    let done = DispatchSemaphore(value: 0)
                    Task { @MainActor in delivery.deliver(); done.signal() }; _ = done.wait(timeout: .now() + 5)
                }
                return bytes
            })
            let editor = EditorSession(store: store, exportRegistry: ExportFileRegistry(root: root.appendingPathComponent("exports")))
            await editor.loadIfNeeded(); editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
            delivery.editor = editor; gate.arm()
            let file = await editor.exportBackup()
            XCTAssertNil(file); XCTAssertNotNil(editor.operationError); XCTAssertEqual(editor.strokeCount, unsupported ? 1 : 2)
            if unsupported { guard case .failed = editor.saveState else { return XCTFail("must retain failed drawing") } }
            else { await editor.flush(); let disk = try await store.load(); XCTAssertEqual(disk?.document, editor.document) }
        }
    }
    func testPDFKitRejectsCRCValidButInvalidOrMismatchedPDFBeforeCatalogAddition() async throws {
        let root = try directory()
        for badGeometry in [false, true] {
            let raw = badGeometry ? try PDFFixture.data(rotations: [90]) : Data("not a PDF".utf8)
            let asset = PDFAsset(originalFilename: "bad.pdf", pageCount: 1, byteCount: raw.count)
            let page = NotePage(width: 300, height: 450, pdfSource: PDFPageSource(assetID: asset.id, index: 0,
                mediaBox: PageRect(x: 0, y: 0, width: 300, height: 450), cropBox: PageRect(x: 0, y: 0, width: 300, height: 450), rotation: 0))
            let document = NoteDocument(title: "bad", pages: [page], pdfAssets: [asset])
            let pdf = root.appendingPathComponent("source.pdf"), archive = root.appendingPathComponent("bad.minote")
            try raw.write(to: pdf); try await NoteBackup().export(document: document, assetURLs: [asset.id: pdf], destination: archive)
            let library = LibrarySession(store: LibraryStore(directory: root.appendingPathComponent(UUID().uuidString)))
            await library.load(); await library.restoreBackup(from: archive, folderID: nil)
            XCTAssertTrue(library.notes.isEmpty); XCTAssertNotNil(library.operationError)
        }
    }
    func testLateDrawingDuringArchiveWriteIsNotReleasedAsLatestBackup() async throws {
        for unsupported in [false, true] {
            let root = try directory(), delivery = BackupLateDrawing(), gate = BackupReadGate()
            delivery.unsupported = unsupported; gate.arm()
            let service = NoteBackup(chunkWriter: { handle, bytes in
                try handle.write(contentsOf: bytes)
                if gate.fire() {
                    let done = DispatchSemaphore(value: 0)
                    Task { @MainActor in delivery.deliver(); done.signal() }; _ = done.wait(timeout: .now() + 5)
                }
            })
            let registry = ExportFileRegistry(root: root.appendingPathComponent("exports"))
            let editor = EditorSession(store: DocumentStore(directory: root.appendingPathComponent("source")), exportRegistry: registry, backupService: service)
            await editor.loadIfNeeded(); editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()])); delivery.editor = editor
            let file = await editor.exportBackup()
            XCTAssertNil(file); XCTAssertNotNil(editor.operationError); XCTAssertEqual(editor.strokeCount, unsupported ? 1 : 2)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("exports").path)
            XCTAssertEqual(leftovers, ["registry.json"])
            if !unsupported { await editor.flush(); XCTAssertEqual(editor.saveState, .saved) }
        }
    }
    func testArchiveDiskFailureOrCancellationKeepsDrawingAndReleasesOwnFiles() async throws {
        for cancelled in [false, true] {
            let root = try directory(), registry = ExportFileRegistry(root: root.appendingPathComponent("exports"))
            let service = NoteBackup(chunkWriter: { _, _ in
                if cancelled { throw CancellationError() }; throw POSIXError(.ENOSPC)
            })
            let editor = EditorSession(store: DocumentStore(directory: root.appendingPathComponent("source")), exportRegistry: registry, backupService: service)
            await editor.loadIfNeeded(); editor.receiveDrawing(PKDrawing(strokes: [sampleStroke()]))
            let file = await editor.exportBackup()
            XCTAssertNil(file); XCTAssertEqual(editor.strokeCount, 1); XCTAssertEqual(editor.saveState, .saved); XCTAssertFalse(editor.isProcessing)
            XCTAssertNotNil(editor.operationError)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("exports").path), ["registry.json"])
        }
    }
    func testActiveEditorCannotBePurged() async throws {
        let root = try directory(), library = LibrarySession(store: LibraryStore(directory: root))
        await library.load(); await library.createNote(title: "keep", folderID: nil)
        let id = try XCTUnwrap(library.notes.first?.id); await library.openNote(id)
        await library.purgeNote(id)
        XCTAssertEqual(library.selectedEditor?.document?.id, id); XCTAssertEqual(library.notes.count, 1); XCTAssertNotNil(library.operationError)
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
}
@MainActor private final class BackupLateDrawing {
    var editor: EditorSession?
    var unsupported = false
    func deliver() { editor?.receiveDrawing(PKDrawing(strokes: unsupported ? [sampleStroke(ink: .pencil)] : [sampleStroke(), sampleStroke(offset: 70)])) }
}
private final class BackupReadGate: @unchecked Sendable {
    private let lock = NSLock(); private var armed = false
    func arm() { lock.lock(); defer { lock.unlock() }; armed = true }
    func fire() -> Bool { lock.lock(); defer { lock.unlock() }; if armed { armed = false; return true }; return false }
}
