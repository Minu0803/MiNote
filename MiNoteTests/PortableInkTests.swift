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
            let source = PDFPageSource(index: i, mediaBox: PageRect(x: 10, y: 20, width: 400, height: 600),
                cropBox: PageRect(x: 40, y: 70, width: 300, height: 450), rotation: rotation)
            var strokes: [InkStroke] = []
            if i == 0 { var stroke = ink[0]; stroke.id = id(105); strokes = [stroke] }
            pages.append(NotePage(id: id(11 + i), width: rotation % 180 == 0 ? 300 : 450,
                height: rotation % 180 == 0 ? 450 : 300, strokes: strokes, pdfSource: source))
        }
        return NoteDocument(id: id(1), revision: 40, title: "MiNote portable ink fixture", pages: pages,
            pdfAsset: PDFAsset(id: id(2), originalFilename: "source.pdf", pageCount: 4,
                byteCount: try PDFFixture.data().count, importedAt: 1_700_000_001), lastOpenedPageID: id(10))
    }
}

@MainActor func fixtureURL(_ name: String, extension ext: String = "json") throws -> URL {
    try XCTUnwrap(Bundle(for: PortableInkTests.self).url(forResource: name, withExtension: ext, subdirectory: "PortableInk"))
}

@MainActor func fixtureDocument(_ name: String) throws -> NoteDocument {
    try DocumentCodec.decode(Data(contentsOf: fixtureURL(name)))
}
