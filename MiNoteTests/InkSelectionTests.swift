import XCTest
import PencilKit
import MiNoteCore
@testable import MiNote

@MainActor final class InkSelectionTests: XCTestCase {
    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [SelectionPoint] {
        [.init(x:x,y:y),.init(x:x+w,y:y),.init(x:x+w,y:y+h),.init(x:x,y:y+h)]
    }
    func testIdenticalStrokesSelectBothPersistentIDsAndCrossingCentreLine() throws {
        let native = PKDrawing(strokes: [sampleStroke(),sampleStroke()])
        let portable = try InkAdapter.encode(native,preserving:[])
        let ids = try InkSelection.selectedIDs(in:native,portable:portable,polygon:box(20,24,5,4))
        XCTAssertEqual(ids,Set(portable.map(\.id)))
        XCTAssertEqual(ids.count,2)
        XCTAssertTrue(try InkSelection.selectedIDs(in:native,portable:portable,polygon:box(10,50,60,10)).isEmpty)
    }
    func testRotatedTransformIsAppliedOnceAndMismatchedDrawingIsRejected() throws {
        var stroke = sampleStroke(); stroke.transform = CGAffineTransform(a:0,b:1,c:-1,d:0,tx:300,ty:20)
        let native = PKDrawing(strokes:[stroke])
        let portable = try InkAdapter.encode(native,preserving:[])
        XCTAssertEqual(try InkSelection.selectedIDs(in:native,portable:portable,polygon:box(275,25,10,50)),Set(portable.map(\.id)))
        XCTAssertTrue(try InkSelection.selectedIDs(in:native,portable:portable,polygon:box(10,20,50,10)).isEmpty)
        XCTAssertThrowsError(try InkSelection.selectedIDs(in:native,portable:[],polygon:box(275,25,10,50)))
        XCTAssertThrowsError(try InkSelection.selectedIDs(in:PKDrawing(strokes:[sampleStroke(ink:.pencil)]),portable:portable,polygon:box(0,0,100,100)))
    }
    func testMoveVersionAliasesKeepIDsAcrossUndoAndSecondMove() throws {
        let original = try InkAdapter.encode(PKDrawing(strokes:[sampleStroke()]),preserving:[])
        var moved = original; moved[0].transform.tx = 35; moved[0].transform.ty = -9
        XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(original),preserving:moved,aliases:original),original)
        var twice = moved; twice[0].transform.tx = 65
        XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(twice),preserving:twice,aliases:original+moved),twice)
        XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(moved),preserving:twice,aliases:original+moved),moved)
        let appended = PKDrawing(strokes:try InkAdapter.decode(twice).strokes + [sampleStroke(offset:80)])
        let added = try InkAdapter.encode(appended,preserving:twice,aliases:original+moved)
        XCTAssertEqual(added[0],twice[0]); XCTAssertNotEqual(added[1].id,original[0].id)
        XCTAssertEqual(try InkAdapter.encode(PKDrawing(strokes:[appended.strokes[1]]),preserving:added,aliases:original+moved),[added[1]])
    }
    func testHistoricalAliasCannotStealIdenticalOtherStrokeID() throws {
        let native = PKDrawing(strokes:[sampleStroke(),sampleStroke()])
        let original = try InkAdapter.encode(native,preserving:[])
        var moved = original; moved[0].transform.tx = 35
        XCTAssertEqual(try InkAdapter.encode(InkAdapter.decode(moved),preserving:moved,aliases:original),moved)
        XCTAssertThrowsError(try InkAdapter.encode(PKDrawing(strokes:[sampleStroke()]),preserving:moved,aliases:original))
    }
    func testOverlayCoordinatesStayInPagePointsAtFitZoomAndRotation() throws {
        let host = PageZoomHost(frame:CGRect(x:0,y:0,width:834,height:900))
        for size in [CGSize(width:595,height:842),CGSize(width:450,height:300),CGSize(width:300,height:450)] {
            host.configurePage(size:size,pdfPage:nil); host.layoutIfNeeded()
            let scroll = try XCTUnwrap(host.subviews.compactMap { $0 as? UIScrollView }.first)
            for scale in [scroll.minimumZoomScale,scroll.minimumZoomScale*2,scroll.minimumZoomScale*5] {
                scroll.setZoomScale(scale,animated:false); host.layoutIfNeeded()
                for point in [CGPoint(x:30,y:45),CGPoint(x:60,y:30)] {
                    let screen = host.convert(point,from:host.canvas)
                    let document = host.lasso.convert(screen,from:host)
                    XCTAssertEqual(document.x,point.x,accuracy:0.0001); XCTAssertEqual(document.y,point.y,accuracy:0.0001)
                }
            }
            host.frame = CGRect(x:0,y:0,width:900,height:834); host.layoutIfNeeded()
            let origin = host.lasso.convert(host.convert(CGPoint(x:30,y:45),from:host.canvas),from:host)
            XCTAssertEqual(origin.x,30,accuracy:0.0001); XCTAssertEqual(origin.y,45,accuracy:0.0001)
        }
    }
    func testOverlayTapZeroMoveAndInputModeCancellationDoNotCommit() throws {
        let drawing=PKDrawing(strokes:[sampleStroke()]), portable=try InkAdapter.encode(drawing,preserving:[])
        let overlay=LassoOverlay(); var moves:[CGSize]=[], selections:[[SelectionPoint]]=[]
        func configure(_ finger: Bool) {
            overlay.configure(drawing:drawing,portable:portable,selectedIDs:Set(portable.map(\.id)),enabled:true,fingerEnabled:finger,
                onSelect:{selections.append($0)},onMove:{moves.append(CGSize(width:$0,height:$1))},onError:{_ in XCTFail("Unexpected error")})
        }
        configure(true)
        overlay.begin(at:CGPoint(x:25,y:26)); overlay.end(at:CGPoint(x:25,y:26))
        XCTAssertEqual(moves,[.zero]); XCTAssertTrue(selections.isEmpty)
        overlay.begin(at:CGPoint(x:120,y:120)); overlay.end(at:CGPoint(x:120,y:120))
        XCTAssertEqual(selections,[[]]); XCTAssertEqual(moves.count,1)
        overlay.beginGesture(initialContact:CGPoint(x:25,y:26),location:CGPoint(x:55,y:11))
        XCTAssertEqual(overlay.previewOffset,CGSize(width:30,height:-15))
        configure(false); overlay.end(at:CGPoint(x:55,y:11))
        XCTAssertEqual(moves.count,1); XCTAssertEqual(overlay.previewOffset,.zero)
        let pan=try XCTUnwrap(overlay.gestureRecognizers?.first as? UIPanGestureRecognizer)
        XCTAssertEqual(pan.allowedTouchTypes,[NSNumber(value:UITouch.TouchType.pencil.rawValue)])
        let host=PageZoomHost(frame:CGRect(x:0,y:0,width:834,height:900)); host.layoutIfNeeded()
        let scroll=try XCTUnwrap(host.subviews.first as? UIScrollView)
        host.setFingerDrawing(true); XCTAssertEqual(scroll.panGestureRecognizer.minimumNumberOfTouches,2)
        host.setFingerDrawing(false); XCTAssertEqual(scroll.panGestureRecognizer.minimumNumberOfTouches,1)
    }
    func testScaledCurveUsesDocumentSpaceSamplingForSmallLasso() throws {
        let points=[CGPoint(x:0,y:0),CGPoint(x:30,y:60),CGPoint(x:60,y:0)].enumerated().map { i,p in
            PKStrokePoint(location:p,timeOffset:Double(i)*0.1,size:CGSize(width:2,height:2),opacity:1,force:1,azimuth:0,altitude:1)
        }
        let stroke=PKStroke(ink:PKInk(.pen,color:.blue),path:PKStrokePath(controlPoints:points,creationDate:Date()),transform:CGAffineTransform(scaleX:100,y:100))
        let drawing=PKDrawing(strokes:[stroke]), portable=try InkAdapter.encode(drawing,preserving:[])
        let onCurve=stroke.path.interpolatedLocation(at:0.52).applying(stroke.transform)
        XCTAssertEqual(try InkSelection.selectedIDs(in:drawing,portable:portable,polygon:box(onCurve.x-0.01,onCurve.y-0.01,0.02,0.02)),Set(portable.map(\.id)))
    }
}
