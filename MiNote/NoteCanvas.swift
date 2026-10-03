import Combine
import MiNoteCore
import PencilKit
import PDFKit
import SwiftUI
import UIKit

@MainActor
final class CanvasReference: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    weak var canvas: PKCanvasView?

    func undo(in session: EditorSession) {
        guard !session.isProcessing else { return }
        canvas?.undoManager?.undo()
        refresh()
    }
    func redo(in session: EditorSession) {
        guard !session.isProcessing else { return }
        canvas?.undoManager?.redo()
        refresh()
    }
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
    private let paper = PDFPaperView()
    let canvas = PKCanvasView()
    private var pageSize = CGSize(width: 595.2756, height: 841.8898)
    private var hasInitialZoom = false
    private var priorFit: CGFloat = 0

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

    func configurePage(size: CGSize, pdfPage: PDFPage?, paperStyle: PaperStyle = .blank) {
        if pageSize != size || !hasInitialZoom {
            scrollView.zoomScale = 1
            pageSize = size
            page.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
            hasInitialZoom = false
        }
        paper.paperStyle = paperStyle
        if paper.pdfPage !== pdfPage { paper.pdfPage = pdfPage }
        scrollView.accessibilityLabel = pdfPage == nil ? paperStyle.title : "PDF 필기 페이지"
        setNeedsLayout()
    }

    func setFingerDrawing(_ enabled: Bool) {
        scrollView.panGestureRecognizer.minimumNumberOfTouches = enabled ? 2 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        if !hasInitialZoom {
            scrollView.zoomScale = 1
            page.frame = CGRect(origin: .zero, size: pageSize)
            scrollView.contentSize = pageSize
        }
        paper.frame = page.bounds
        canvas.frame = page.bounds
        let fit = max(0.1, min((bounds.width - 40) / pageSize.width, (bounds.height - 40) / pageSize.height))
        scrollView.minimumZoomScale = fit
        scrollView.maximumZoomScale = max(fit * 5, fit + 0.5)
        if !hasInitialZoom || abs(scrollView.zoomScale - priorFit) < 0.001 {
            scrollView.zoomScale = fit
            hasInitialZoom = true
        } else if scrollView.zoomScale < fit {
            scrollView.zoomScale = fit
        }
        priorFit = fit
        centerPage()
        if !scrollView.isZooming { updatePaperResolution() }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { page }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPage() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updatePaperResolution()
    }

    private func updatePaperResolution() {
        guard paper.pdfPage != nil else { return }
        let displayScale = max(1, traitCollection.displayScale)
        // A single PDF backing image stays within 4096² pixels (64 MiB RGBA).
        let limit = 4096 / max(pageSize.width, pageSize.height)
        let resolution = min(displayScale * scrollView.zoomScale, limit)
        if abs(paper.contentScaleFactor - resolution) > 0.01 {
            paper.contentScaleFactor = resolution
            paper.setNeedsDisplay()
        }
    }

    private func centerPage() {
        let horizontal = max(0, (scrollView.bounds.width - pageSize.width * scrollView.zoomScale) * 0.5)
        let vertical = max(0, (scrollView.bounds.height - pageSize.height * scrollView.zoomScale) * 0.5)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
}

struct NoteCanvas: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
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
        if let page = session.currentPage {
            host.configurePage(size: CGSize(width: page.width, height: page.height), pdfPage: session.currentPDFPage, paperStyle: page.paper)
        }
        host.setFingerDrawing(fingerDrawingEnabled)
        host.canvas.isUserInteractionEnabled = isEnabled && !session.isProcessing
        configure(host.canvas)
        Task { @MainActor in reference.refresh() }
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
        if let page = session.currentPage {
            host.configurePage(size: CGSize(width: page.width, height: page.height), pdfPage: session.currentPDFPage, paperStyle: page.paper)
        }
        host.setFingerDrawing(fingerDrawingEnabled)
        host.canvas.isUserInteractionEnabled = isEnabled && !session.isProcessing
        configure(host.canvas)
    }

    static func dismantleUIView(_ host: PageZoomHost, coordinator: Coordinator) {
        host.canvas.delegate = nil
        if coordinator.reference.canvas === host.canvas { coordinator.reference.canvas = nil }
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
        let pageID: UUID?
        let generation: UUID
        init(session: EditorSession, reference: CanvasReference) {
            self.session = session; self.reference = reference; self.pageID = session.currentPage?.id; self.generation = session.canvasGeneration
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingSessionDrawing, pageID == session.currentPage?.id, generation == session.canvasGeneration else { return }
            session.receiveDrawing(canvasView.drawing)
            reference.refresh()
        }
    }
}

enum Brush: String, CaseIterable { case pen, marker, eraser }
