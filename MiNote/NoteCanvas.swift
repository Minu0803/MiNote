import Combine
import MiNoteCore
import PencilKit
import SwiftUI
import UIKit

@MainActor
final class CanvasReference: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    weak var canvas: PKCanvasView?

    func undo() { canvas?.undoManager?.undo(); refresh() }
    func redo() { canvas?.undoManager?.redo(); refresh() }
    func refresh() {
        let nextUndo = canvas?.undoManager?.canUndo ?? false
        let nextRedo = canvas?.undoManager?.canRedo ?? false
        if canUndo != nextUndo { canUndo = nextUndo }
        if canRedo != nextRedo { canRedo = nextRedo }
    }
}

final class PageZoomHost: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let page = UIView()
    private let paper = UIView()
    let canvas = PKCanvasView()
    private let pageSize = CGSize(width: 595.2756, height: 841.8898)
    private var hasInitialZoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.accessibilityIdentifier = "noteCanvas"
        scrollView.accessibilityLabel = "A4 필기 페이지"
        // One-finger contact is reserved for the selected PencilKit tool.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.addSubview(page)
        addSubview(scrollView)

        page.backgroundColor = .clear
        paper.backgroundColor = .white
        paper.layer.cornerRadius = 3
        paper.layer.shadowColor = UIColor.black.cgColor
        paper.layer.shadowOpacity = 0.13
        paper.layer.shadowRadius = 14
        paper.layer.shadowOffset = CGSize(width: 0, height: 5)
        page.addSubview(paper)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.maximumSupportedContentVersion = .version1
        canvas.drawingPolicy = .pencilOnly
        canvas.accessibilityIdentifier = "inkCanvas"
        page.addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        page.frame = CGRect(origin: .zero, size: pageSize)
        paper.frame = page.bounds
        canvas.frame = page.bounds
        scrollView.contentSize = pageSize
        let fit = max(0.1, min((bounds.width - 40) / pageSize.width, (bounds.height - 40) / pageSize.height))
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 5, fit + 0.5)
        if !hasInitialZoom {
            scrollView.zoomScale = fit
            hasInitialZoom = true
        } else if scrollView.zoomScale < fit {
            scrollView.zoomScale = fit
        }
        centerPage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { page }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPage() }

    private func centerPage() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) * 0.5)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) * 0.5)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}

struct NoteCanvas: UIViewRepresentable {
    @ObservedObject var session: EditorSession
    @ObservedObject var reference: CanvasReference
    let tool: Brush
    let color: UIColor
    let width: CGFloat
    let fingerDrawingEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(session: session, reference: reference) }

    func makeUIView(context: Context) -> PageZoomHost {
        let host = PageZoomHost()
        host.canvas.delegate = context.coordinator
        reference.canvas = host.canvas
        configure(host.canvas)
        return host
    }

    func updateUIView(_ host: PageZoomHost, context: Context) {
        context.coordinator.session = session
        context.coordinator.reference = reference
        if host.canvas.drawing != session.drawing {
            context.coordinator.isApplyingSessionDrawing = true
            host.canvas.drawing = session.drawing
            context.coordinator.isApplyingSessionDrawing = false
        }
        reference.canvas = host.canvas
        configure(host.canvas)
    }

    static func dismantleUIView(_ host: PageZoomHost, coordinator: Coordinator) {
        coordinator.reference.canvas = nil
    }

    private func configure(_ canvas: PKCanvasView) {
        canvas.drawingPolicy = fingerDrawingEnabled ? .anyInput : .pencilOnly
        switch tool {
        case .pen: canvas.tool = PKInkingTool(.pen, color: color, width: width)
        case .marker: canvas.tool = PKInkingTool(.marker, color: color, width: width)
        case .eraser: canvas.tool = PKEraserTool(.vector)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var session: EditorSession
        var reference: CanvasReference
        var isApplyingSessionDrawing = false
        init(session: EditorSession, reference: CanvasReference) {
            self.session = session; self.reference = reference
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingSessionDrawing else { return }
            session.receiveDrawing(canvasView.drawing)
            reference.refresh()
        }
    }
}

enum Brush: String, CaseIterable { case pen, marker, eraser }
