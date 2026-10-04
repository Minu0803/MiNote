import MiNoteCore
import PencilKit
import UIKit

/// A transient page-space gesture surface. Only a completed move changes ink.
final class LassoOverlay: UIView, UIGestureRecognizerDelegate {
    private var samples: [CGPoint] = []
    private var moveOrigin: CGPoint?
    private var selectionBounds = CGRect.null
    private var ghost: UIImage?
    private(set) var previewOffset = CGSize.zero
    private var onSelect: (([SelectionPoint]) throws -> Void)?
    private var onMove: ((Double,Double) throws -> Void)?
    private var onError: ((Error) -> Void)?
    private lazy var pan: LassoPanGesture = {
        let recognizer = LassoPanGesture(target:self,action:#selector(handlePan))
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
        return recognizer
    }()
    override init(frame: CGRect) {
        super.init(frame:frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        accessibilityIdentifier = "lassoCanvas"
        accessibilityLabel = "올가미 선택 및 이동"
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(drawing: PKDrawing, portable: [InkStroke], selectedIDs: Set<UUID>, enabled: Bool, fingerEnabled: Bool,
                   onSelect: @escaping ([SelectionPoint]) throws -> Void, onMove: @escaping (Double,Double) throws -> Void,
                   onError: @escaping (Error) -> Void) {
        let strokes = zip(drawing.strokes,portable).filter { selectedIDs.contains($0.1.id) }.map(\.0)
        let nextBounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        if !enabled || nextBounds != selectionBounds { cancelPreview() }
        selectionBounds = nextBounds
        if !nextBounds.isNull, nextBounds.width.isFinite, nextBounds.height.isFinite,
           nextBounds.width > 0, nextBounds.height > 0 {
            ghost = PKDrawing(strokes:strokes).image(from:nextBounds,scale:min(1,1024/max(nextBounds.width,nextBounds.height)))
        } else { ghost = nil }
        self.onSelect=onSelect; self.onMove=onMove; self.onError=onError
        let types = fingerEnabled ? [UITouch.TouchType.direct.rawValue,UITouch.TouchType.pencil.rawValue] : [UITouch.TouchType.pencil.rawValue]
        let allowed = types.map { NSNumber(value:$0) }
        if pan.allowedTouchTypes != allowed { cancelPreview(); pan.allowedTouchTypes=allowed }
        isUserInteractionEnabled = enabled
        setNeedsDisplay()
    }
    func begin(at point: CGPoint) {
        guard isUserInteractionEnabled else { return }
        cancelPreview()
        if !selectionBounds.isNull, selectionBounds.insetBy(dx:-8,dy:-8).contains(point) { moveOrigin=point }
        else { samples=[point] }
        setNeedsDisplay()
    }
    func beginGesture(initialContact: CGPoint, location: CGPoint) {
        // UIPan begins after its movement threshold. Hit-test the initial contact,
        // rather than the delayed location that may already be outside thin ink.
        begin(at:initialContact)
        continueGesture(at:location)
    }
    func continueGesture(at point: CGPoint) {
        if let origin=moveOrigin { previewOffset=CGSize(width:point.x-origin.x,height:point.y-origin.y) }
        else if !samples.isEmpty, samples.last != point { samples.append(point) }
        setNeedsDisplay()
    }
    func end(at point: CGPoint) {
        guard moveOrigin != nil || !samples.isEmpty else { return }
        continueGesture(at:point)
        let moving = moveOrigin != nil, offset=previewOffset, polygon=samples
        cancelPreview()
        do {
            if moving { try onMove?(Double(offset.width),Double(offset.height)) }
            else if Set(polygon.map { SelectionPoint(x:$0.x,y:$0.y) }).count >= 3 {
                try onSelect?(polygon.map { SelectionPoint(x:$0.x,y:$0.y) })
            } else { try onSelect?([]) }
        } catch { onError?(error) }
    }
    func cancelPreview() {
        moveOrigin=nil; samples=[]; previewOffset = .zero; setNeedsDisplay()
    }
    func cancelGesture() {
        cancelPreview()
        if pan.state == .began || pan.state == .changed { pan.isEnabled=false; pan.isEnabled=true }
    }
    @objc private func handlePan(_ recognizer: LassoPanGesture) {
        let point=recognizer.location(in:self)
        switch recognizer.state {
        case .began:
            guard let contact=recognizer.initialContact else { cancelPreview(); return }
            beginGesture(initialContact:contact,location:point)
        case .changed: continueGesture(at:point)
        case .ended: end(at:point)
        default: cancelPreview()
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // The enclosing scroll view owns pinch/two-finger navigation.
        other.view is UIScrollView
    }
    override func draw(_ rect: CGRect) {
        UIColor.systemBlue.setStroke()
        if !selectionBounds.isNull {
            let bounds=selectionBounds.offsetBy(dx:previewOffset.width,dy:previewOffset.height)
            if moveOrigin != nil { ghost?.draw(in:bounds,blendMode:.normal,alpha:0.5) }
            let path=UIBezierPath(rect:bounds.insetBy(dx:-4,dy:-4)); path.lineWidth=1.5
            path.setLineDash([5,3],count:2,phase:0); path.stroke()
        }
        if let first=samples.first {
            let path=UIBezierPath(); path.move(to:first)
            for point in samples.dropFirst() { path.addLine(to:point) }
            path.close(); UIColor.systemBlue.withAlphaComponent(0.08).setFill(); path.fill()
            path.lineWidth=1.5; path.stroke()
        }
    }
}

/// UIPan reports zero translation at .began on supported OS versions. Retain the
/// original contact independently, before the recognizer's movement threshold.
private final class LassoPanGesture: UIPanGestureRecognizer {
    private(set) var initialContact: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if initialContact == nil { initialContact=touches.first?.location(in:view) }
        super.touchesBegan(touches,with:event)
    }
    override func reset() { super.reset(); initialContact=nil }
}
