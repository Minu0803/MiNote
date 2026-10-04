import MiNoteCore
import PencilKit
import XCTest
@testable import MiNote

@MainActor final class PortableInkTests: XCTestCase {
    func testGeneratePencilKitFixture() throws {
        let document = try PortableFixture.make()
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PortableInkGenerated")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try DocumentCodec.encode(document).write(to: output.appendingPathComponent("source.json"), options: .atomic)
        try PDFFixture.data().write(to: output.appendingPathComponent("source.pdf"), options: .atomic)
        XCTAssertEqual(document.pages[0].strokes[0].points[1].secondaryScale, 1.5, accuracy: 0.00001)
        for page in document.pages {
            XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(page.strokes), preserving: page.strokes), page.strokes)
        }
    }

    func testSharedFixtureReconstructsEditablePencilKitStrokes() throws {
        let document = try fixtureDocument("source")
        for page in document.pages {
            let restored = try InkAdapter.decode(page.strokes)
            XCTAssertEqual(try InkAdapter.encode(restored, preserving: page.strokes), page.strokes)
        }
        XCTAssertEqual(document.pages[0].strokes[0].transform.tx, 5)
        XCTAssertEqual(document.pages[0].strokes[3].transform.b, 1)
        XCTAssertEqual(document.pages[0].strokes[1].color.alpha, 0.35, accuracy: 0.00001)
    }

    func testSmallActualTransformEditIsNotHiddenByPointNormalization() throws {
        let original = try fixtureDocument("source").pages[0].strokes[0]
        let restored = try InkAdapter.decode([original]).strokes[0]
        var transform = restored.transform
        transform.tx += 0.0001
        let changed = PKStroke(ink: restored.ink, path: restored.path, transform: transform, randomSeed: restored.randomSeed)
        let encoded = try InkAdapter.encode(PKDrawing(strokes: [changed]), preserving: [original])
        XCTAssertEqual(encoded[0].transform.tx, 5.0001, accuracy: 0.00000001)
        XCTAssertNotEqual(encoded[0], original)
    }

    func testConflictingRawAndReconstructedFingerprintsKeepOrderedProvenance() throws {
        let a = try fixtureDocument("source").pages[0].strokes[0]
        var b = try InkAdapter.encode(InkAdapter.decode([a]), preserving: [])[0]
        b.id = PortableFixture.id(999)
        let known = [a, b]
        XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(known), preserving: known), known)
    }

    func testDuplicateShapeDeletionUsesRemainingStrokeOrderOrRejectsAmbiguity() throws {
        let known = try fixtureDocument("source").pages[0].strokes
        let drawing = try InkAdapter.decode(known)
        XCTAssertEqual(try InkAdapter.encode(PKDrawing(strokes: Array(drawing.strokes.dropFirst())), preserving: known), Array(known.dropFirst()))
        var duplicate = known[0]; duplicate.id = PortableFixture.id(999)
        let ambiguous = [known[0], duplicate]
        XCTAssertThrowsError(try InkAdapter.encode(InkAdapter.decode([duplicate]), preserving: ambiguous))
    }

    func testAmbiguousIdentityRetainsVisibleInkAndLastSavedDocument() async throws {
        let stroke = try fixtureDocument("source").pages[0].strokes[0]
        var duplicate = stroke; duplicate.id = PortableFixture.id(999)
        let original = NoteDocument(title: "Ambiguous duplicate", pages: [NotePage(strokes: [stroke, duplicate])])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DocumentStore(directory: directory)
        try await store.save(original)
        let session = EditorSession(store: store)
        await session.loadIfNeeded()
        let remaining = PKDrawing(strokes: Array(session.drawing.strokes.dropFirst()))
        session.receiveDrawing(remaining)
        XCTAssertEqual(session.strokeCount, 1)
        XCTAssertEqual(session.document, original)
        guard case .failed = session.saveState else { return XCTFail("Ambiguous identity must block serialization") }
        await session.flush()
        let persisted = try await store.load()
        XCTAssertEqual(persisted?.document, original)
    }

    func testJavaScriptAndBrowserResultsCanBeReeditedUndoneSavedAndReopened() async throws {
        for name in ["edited", "browser-edited"] { try await assertEditableRoundtrip(name) }
    }

    func testIndependentV3RoundTripPreservesPagesAssetsAndEditableInk() async throws {
        let fixture = try fixtureDocument("multi-edited")
        XCTAssertEqual(fixture.schemaVersion, 3); XCTAssertEqual(fixture.pdfAssets.count, 2)
        XCTAssertEqual(fixture.deletedPages.count, 1); XCTAssertEqual(fixture.pages[0].paper, .grid)
        XCTAssertTrue(fixture.pages[0].isBookmarked)
        try await assertEditableRoundtrip("multi-edited")
    }
    func testIndependentLassoV3ResultReopensAsEditableInkWithStableMovedID() async throws {
        let source=try fixtureDocument("lasso-source"), moved=try fixtureDocument("lasso-moved"), edited=try fixtureDocument("lasso-edited")
        XCTAssertEqual(moved.pages[1].strokes[0].id,source.pages[1].strokes[0].id)
        XCTAssertEqual(moved.pages[1].strokes[0].transform.tx,35); XCTAssertEqual(moved.pages[1].strokes[0].transform.ty,-9)
        XCTAssertEqual(edited.pages[1],moved.pages[1]); XCTAssertEqual(edited.revision,44)
        try await assertEditableRoundtrip("lasso-edited")
    }

    func testGenerateV3PencilKitFixture() throws {
        var document = try PortableFixture.make()
        document.pages[0].paper = .grid; document.pages[0].isBookmarked = true
        let deleted = document.pages.removeLast()
        document.deletedPages = [DeletedPage(page: deleted, originalIndex: 4, deletedAt: 1_700_000_002)]
        let original = document.pdfAssets[0]
        let second = PDFAsset(id: PortableFixture.id(3), originalFilename: original.originalFilename,
            pageCount: original.pageCount, byteCount: original.byteCount, importedAt: original.importedAt)
        document.pdfAssets.append(second)
        var page = document.pages[1]; page.id = PortableFixture.id(90); page.isBookmarked = true
        if var source = page.pdfSource { source.assetID = second.id; page.pdfSource = source }
        for i in page.strokes.indices { page.strokes[i].id = PortableFixture.id(190 + i) }
        document.pages.append(page)
        for page in document.pages + document.deletedPages.map(\.page) {
            XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(page.strokes), preserving: page.strokes), page.strokes)
        }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PortableInkGenerated/multi-source.json")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DocumentCodec.encode(document).write(to: output, options: .atomic)
    }

    private func assertEditableRoundtrip(_ name: String) async throws {
            let imported = try fixtureDocument(name)
            for page in imported.pages {
                XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(page.strokes), preserving: page.strokes), page.strokes)
            }
            let restored = try InkAdapter.decode(imported.pages[0].strokes)
            let transformed = restored.strokes[0].path[0].location.applying(restored.strokes[0].transform)
            XCTAssertEqual(transformed.x, 97, accuracy: 0.01)
            XCTAssertEqual(transformed.y, 98, accuracy: 0.01)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let bytes = try Data(contentsOf: fixtureURL("source", extension: "pdf"))
            for asset in imported.pdfAssets {
                try bytes.write(to: directory.appendingPathComponent(asset.relativePath))
            }
            let store = DocumentStore(directory: directory)
            try await store.save(imported)
            let session = EditorSession(store: store, saveDelay: .seconds(60))
            await session.loadIfNeeded()
            XCTAssertNil(session.loadError)
            XCTAssertEqual(session.document, imported)
            if session.currentPage?.id != imported.pages[0].id { await session.selectPage(0) }

            let canvas = PortableCommandCanvas()
            canvas.manager.groupsByEvent = false
            let reference = CanvasReference(); reference.canvas = canvas
            let coordinator = NoteCanvas.Coordinator(session: session, reference: reference)
            canvas.drawing = session.drawing
            // Programmatic drawing assignments do not model a Pencil gesture's
            // undo registration. Register snapshots explicitly, then exercise the
            // production CanvasReference and coordinator with a real UndoManager.
            canvas.onChange = { coordinator.canvasViewDrawingDidChange($0) }
            let newStroke = sampleStroke(offset: 320)
            let appended = PKDrawing(strokes: canvas.drawing.strokes + [newStroke])
            canvas.manager.beginUndoGrouping(); canvas.apply(appended); canvas.manager.endUndoGrouping()
            let addedID = try XCTUnwrap(session.currentPage?.strokes.last?.id)
            XCTAssertEqual(session.strokeCount, 5)
            let removed = PKDrawing(strokes: Array(canvas.drawing.strokes.dropFirst()))
            canvas.manager.beginUndoGrouping(); canvas.apply(removed); canvas.manager.endUndoGrouping()
            XCTAssertEqual(session.strokeCount, 4)
            XCTAssertEqual(canvas.manager.groupingLevel, 0, "Each simulated gesture must be a separate closed undo group")
            reference.undo(in: session)
            XCTAssertEqual(session.currentPage?.strokes.map(\.id), imported.pages[0].strokes.map(\.id) + [addedID])
            reference.redo(in: session)
            XCTAssertEqual(session.strokeCount, 4)
            reference.undo(in: session)
            reference.undo(in: session)
            XCTAssertEqual(session.currentPage?.strokes, imported.pages[0].strokes)
            reference.redo(in: session)
            XCTAssertEqual(session.strokeCount, 5)
            let final = try XCTUnwrap(session.document)
            XCTAssertFalse(final.pages[0].strokes.contains { $0.id == PortableFixture.id(103) })
            XCTAssertEqual(Array(final.pages.dropFirst()), Array(imported.pages.dropFirst()))
            await session.flush(canvas.drawing)
            XCTAssertEqual(session.saveState, .saved)
            let reopened = EditorSession(store: DocumentStore(directory: directory))
            await reopened.loadIfNeeded()
            XCTAssertEqual(reopened.document, final)
            XCTAssertEqual(try InkAdapter.encode(reopened.drawing, preserving: final.pages[0].strokes), final.pages[0].strokes)
            for asset in imported.pdfAssets { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(asset.relativePath)), bytes) }
            XCTAssertEqual(final.pdfAssets, imported.pdfAssets)
            XCTAssertEqual(final.deletedPages, imported.deletedPages)
            XCTAssertEqual(final.pages[0].paper, imported.pages[0].paper)
            XCTAssertEqual(final.pages[0].isBookmarked, imported.pages[0].isBookmarked)
    }
}

@MainActor private final class PortableCommandCanvas: PKCanvasView {
    let manager = UndoManager()
    var onChange: ((PKCanvasView) -> Void)?
    override var undoManager: UndoManager? { manager }
    func apply(_ next: PKDrawing) {
        let previous = drawing
        manager.registerUndo(withTarget: self) { $0.apply(previous) }
        drawing = next
        onChange?(self)
    }
}

@MainActor enum PortableFixture {
    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }

    static func make() throws -> NoteDocument {
        var points: [PKStrokePoint] = []
        for i in 0..<4 {
            let step = CGFloat(i)
            let location = CGPoint(x: 80 + step * 35, y: 100 + CGFloat(i % 2) * 25)
            points.append(PKStrokePoint(location: location, timeOffset: Double(i) * 0.1,
                size: CGSize(width: 3 + step, height: 4 + step), opacity: 0.6 + step * 0.1,
                force: 0.4 + step * 0.1, azimuth: 0.3, altitude: 1.1, secondaryScale: i == 1 ? 1.5 : 1))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        let pen = PKStroke(ink: PKInk(.pen, color: UIColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)),
            path: path, transform: CGAffineTransform(translationX: 5, y: 6), randomSeed: 42)
        let marker = PKStroke(ink: PKInk(.marker, color: UIColor(red: 1, green: 0.7, blue: 0, alpha: 0.35)),
            path: path, transform: CGAffineTransform(a: 1.2, b: 0, c: 0, d: 0.8, tx: 20, ty: 65), randomSeed: 9)
        let rotated = PKStroke(ink: pen.ink, path: path,
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 300, ty: 20), randomSeed: 42)
        var ink = try InkAdapter.encode(PKDrawing(strokes: [pen, marker, pen, rotated]), preserving: [])
        for i in ink.indices { ink[i].id = id(101 + i) }
        var pages = [NotePage(id: id(10), strokes: ink)]
        for (i, rotation) in [0, 90, 180, 270].enumerated() {
            let source = PDFPageSource(assetID: id(2), index: i, mediaBox: PageRect(x: 10, y: 20, width: 400, height: 600),
                cropBox: PageRect(x: 40, y: 70, width: 300, height: 450), rotation: rotation)
            var strokes: [InkStroke] = []
            if i == 0 { var stroke = ink[0]; stroke.id = id(105); strokes = [stroke] }
            pages.append(NotePage(id: id(11 + i), width: rotation % 180 == 0 ? 300 : 450,
                height: rotation % 180 == 0 ? 450 : 300, strokes: strokes, pdfSource: source))
        }
        return NoteDocument(id: id(1), revision: 40, title: "MiNote portable ink fixture", pages: pages,
            pdfAssets: [PDFAsset(id: id(2), originalFilename: "source.pdf", pageCount: 4,
                byteCount: try PDFFixture.data().count, importedAt: 1_700_000_001)], lastOpenedPageID: id(10))
    }
}

@MainActor func fixtureURL(_ name: String, extension ext: String = "json") throws -> URL {
    let bundle = Bundle(for: PortableInkTests.self)
    return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "PortableInk"),
        "Fixture \(name).\(ext), bundle=\(bundle.bundleURL.path), main=\(Bundle.main.bundleURL.path), resources=\(bundle.resourceURL?.path ?? "nil")")
}

@MainActor func fixtureDocument(_ name: String) throws -> NoteDocument {
    try DocumentCodec.decode(Data(contentsOf: fixtureURL(name)))
}
