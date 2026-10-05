import Foundation
import XCTest
@testable import MiNoteCore

final class InkClipboardTests: XCTestCase {
    private func strokes() -> [InkStroke] {
        var pen = fixtureStroke()
        pen.points = [InkPoint(x: 2,y: 3,timeOffset: 0,width: 4,height: 5,opacity: 0.7,force: 0.8,azimuth: 0.2,altitude: 1,secondaryScale: 0.9),
                      InkPoint(x: 8,y: 9,timeOffset: 1,width: 6,height: 7,opacity: 0.6,force: 0.4,azimuth: 0.5,altitude: 0.8,secondaryScale: 1.1)]
        pen.transform = InkTransform(a: 0,b: 2,c: -3,d: 0,tx: 10,ty: -5)
        var marker = pen; marker.id = UUID(); marker.tool = .marker
        return [pen, marker]
    }
    func testPayloadRoundTripPreservesEveryValueAndAffineBounds() throws {
        let source = strokes(), payload = InkClipboardPayload(strokes: source)
        let decoded = try InkClipboardCodec.decode(InkClipboardCodec.encode(payload))
        XCTAssertEqual(decoded, payload)
        let b = try InkClipboardCodec.bounds(of: decoded.strokes)
        // (2,3)->(1,-1), (8,9)->(-17,11). Apply affine exactly once.
        XCTAssertEqual(b.minX, -17); XCTAssertEqual(b.maxX, 1)
        XCTAssertEqual(b.minY, -1); XCTAssertEqual(b.maxY, 11)
        XCTAssertEqual(b.centerX, -8); XCTAssertEqual(b.centerY, 5)
    }
    func testPayloadRejectsMalformedUnknownAndFutureFieldsRecursively() throws {
        let bytes = try InkClipboardCodec.encode(InkClipboardPayload(strokes: strokes()))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String:Any])
        var variants = [[String:Any]]()
        var v = root; v["schemaVersion"] = 2; variants.append(v)
        v = root; v["pdfBytes"] = "unexpected"; variants.append(v)
        v = root; v["strokes"] = []; variants.append(v)
        var ss = root["strokes"] as! [[String:Any]]
        ss[0]["unknown"] = true; v = root; v["strokes"] = ss; variants.append(v)
        ss = root["strokes"] as! [[String:Any]]
        var pts = ss[0]["points"] as! [[String:Any]]; pts[0]["unknown"] = true
        ss[0]["points"] = pts; v = root; v["strokes"] = ss; variants.append(v)
        ss = root["strokes"] as! [[String:Any]]
        var t = ss[0]["transform"] as! [String:Any]; t["extra"] = 1
        ss[0]["transform"] = t; v = root; v["strokes"] = ss; variants.append(v)
        ss = root["strokes"] as! [[String:Any]]
        var c = ss[0]["color"] as! [String:Any]; c["space"] = "future"
        ss[0]["color"] = c; v = root; v["strokes"] = ss; variants.append(v)
        for value in variants { XCTAssertThrowsError(try InkClipboardCodec.decode(JSONSerialization.data(withJSONObject: value))) }
        XCTAssertThrowsError(try InkClipboardCodec.decode(Data("{bad".utf8)))
        XCTAssertThrowsError(try InkClipboardCodec.decode(Data(repeating: 32,count: 8*1024*1024+1)))
    }
    func testPayloadRejectsDuplicateIdentityNonfiniteSingularAndSizeLimits() throws {
        var source = strokes(); source[1].id = source[0].id
        XCTAssertThrowsError(try InkClipboardCodec.encode(InkClipboardPayload(strokes: source)))
        for amount in [Double.nan, .infinity] {
            source = strokes(); source[0].points[0].x = amount
            XCTAssertThrowsError(try InkClipboardCodec.encode(InkClipboardPayload(strokes: source)))
        }
        source = strokes(); source[0].transform = InkTransform(a: 1,b: 2,c: 2,d: 4,tx: 0,ty: 0)
        XCTAssertThrowsError(try InkClipboardCodec.encode(InkClipboardPayload(strokes: source)))
        source = (0..<2001).map { _ in fixtureStroke() }
        XCTAssertThrowsError(try InkClipboardCodec.encode(InkClipboardPayload(strokes: source)))
        var huge = fixtureStroke(); huge.points = Array(repeating: huge.points[0],count: 100001)
        XCTAssertThrowsError(try InkClipboardCodec.encode(InkClipboardPayload(strokes: [huge])))
        huge.points = Array(repeating: huge.points[0],count: 100000)
        XCTAssertThrowsError(try InkClipboardCodec.encode(InkClipboardPayload(strokes: [huge]))) // JSON exceeds 8MiB.
        source = strokes(); source[0].transform.a = .greatestFiniteMagnitude
        XCTAssertThrowsError(try InkClipboardCodec.bounds(of: source))
        XCTAssertThrowsError(try InkClipboardCodec.bounds(of: []))
    }
    func testPastePreservesSourceOrderAndAllDocumentMetadataWithFreshIDs() throws {
        let source = strokes(), page = NotePage(strokes:[fixtureStroke()],paper:.grid,isBookmarked:true)
        let doc = NoteDocument(revision:7,title:"target",pages:[page,NotePage()],deletedPages:[DeletedPage(page:NotePage(strokes:[fixtureStroke()]),originalIndex:0,deletedAt:12)],lastOpenedPageID:page.id)
        let next = try InkCommands.paste(strokes:source,pageID:page.id,dx:20,dy:-10,expectedRevision:7,in:doc)
        XCTAssertEqual(next.revision,8); XCTAssertEqual(next.pages[0].strokes[0],page.strokes[0])
        let pasted = Array(next.pages[0].strokes.dropFirst())
        XCTAssertEqual(pasted.count,2); XCTAssertEqual(Set(pasted.map(\.id)).count,2)
        for (s,p) in zip(source,pasted) {
            XCTAssertFalse(source.map(\.id).contains(p.id))
            XCTAssertEqual(p.transform.tx,30); XCTAssertEqual(p.transform.ty,-15)
            var restored = p; restored.id = s.id; restored.transform = s.transform
            XCTAssertEqual(restored,s)
        }
        var restored = next; restored.revision = 7; restored.pages[0].strokes = page.strokes
        XCTAssertEqual(restored,doc)
        XCTAssertEqual(try DocumentCodec.decode(DocumentCodec.encode(next)),next)
    }
    func testPasteEmptyNoOpStillValidatesAndRejectsStaleOrWrongPage() throws {
        var doc = NoteDocument.blank(); doc.revision = .max; let id = doc.pages[0].id
        XCTAssertEqual(try InkCommands.paste(strokes:[],pageID:id,dx:0,dy:0,expectedRevision:.max,in:doc),doc)
        XCTAssertThrowsError(try InkCommands.paste(strokes:strokes(),pageID:id,dx:0,dy:0,expectedRevision:.max,in:doc))
        XCTAssertThrowsError(try InkCommands.paste(strokes:[],pageID:UUID(),dx:0,dy:0,expectedRevision:.max,in:doc))
        XCTAssertThrowsError(try InkCommands.paste(strokes:[],pageID:id,dx:0,dy:0,expectedRevision:0,in:doc))
        XCTAssertThrowsError(try InkCommands.paste(strokes:[],pageID:id,dx:.nan,dy:0,expectedRevision:.max,in:doc))
        doc.pages[0].width = .nan
        XCTAssertThrowsError(try InkCommands.paste(strokes:[],pageID:id,dx:0,dy:0,expectedRevision:.max,in:doc))
    }
    func testPasteOverflowOrInvalidPayloadIsAtomic() throws {
        let doc = NoteDocument.blank(), id = doc.pages[0].id
        var source = strokes(); source[0].transform.tx = .greatestFiniteMagnitude
        XCTAssertThrowsError(try InkCommands.paste(strokes:source,pageID:id,dx:.greatestFiniteMagnitude,dy:0,expectedRevision:0,in:doc))
        source = strokes(); source[1].id = source[0].id
        XCTAssertThrowsError(try InkCommands.paste(strokes:source,pageID:id,dx:0,dy:0,expectedRevision:0,in:doc))
        XCTAssertEqual(doc.revision,0); XCTAssertTrue(doc.pages[0].strokes.isEmpty)
    }
}
