import MiNoteCore
import PDFKit
import PencilKit
import UIKit

enum PDFExporter {
    /// Original PDF remains untouched. The returned PDF is a share/export copy.
    static func export(_ document: NoteDocument, sourceURL: URL, destination: URL) throws {
        guard sourceURL.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {
            throw PDFError.exportFailed
        }
        try DocumentCodec.validate(document)
        let source = try PDFValidation.open(url: sourceURL, for: document)
        let output = PDFDocument()
        for (index, model) in document.pages.enumerated() {
            let page: PDFPage
            if let sourceIndex = model.pdfSource?.index, let sourcePage = source.page(at: sourceIndex) {
                page = sourcePage
            } else {
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: model.width, height: model.height))
                let bytes = renderer.pdfData { context in context.beginPage() }
                guard let blank = PDFDocument(data: bytes)?.page(at: 0) else { throw PDFError.exportFailed }
                page = blank
            }
            if !model.strokes.isEmpty {
                let drawing = try InkAdapter.decode(model.strokes)
                page.addAnnotation(try DrawingPDFAnnotation(drawing: drawing, page: page))
            }
            output.insert(page, at: index)
        }
        guard let bytes = output.dataRepresentation(options: [PDFDocumentWriteOption.burnInAnnotationsOption: true]),
              let verified = PDFDocument(data: bytes), verified.pageCount == document.pages.count else {
            throw PDFError.exportFailed
        }
        try bytes.write(to: destination, options: .atomic)
    }
}

/// Public PencilKit has no vector drawing export. Rasterize only ink at up to
/// 216 dpi (max 4096px per side); the source PDF text and vectors stay intact.
private final class DrawingPDFAnnotation: PDFAnnotation {
    private let drawing: PKDrawing
    private let geometry: PDFGeometry
    private let mediaOrigin: CGPoint

    init(drawing: PKDrawing, page: PDFPage) throws {
        self.drawing = drawing
        geometry = try PDFGeometry(page: page)
        mediaOrigin = page.bounds(for: .mediaBox).origin
        super.init(bounds: page.bounds(for: .cropBox), forType: .stamp, withProperties: nil)
    }
    required init?(coder: NSCoder) { fatalError("Not archived; annotations are flattened in export") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let visible = CGRect(origin: .zero, size: geometry.size)
        let region = drawing.bounds.intersection(visible)
        guard !region.isNull, region.width > 0, region.height > 0 else { return }
        autoreleasepool {
            let scale = min(3, 4096 / max(region.width, region.height))
            let image = drawing.image(from: region, scale: scale)
            context.saveGState()
            // PDFKit's writer normalizes MediaBox to zero. Source content is
            // translated by it; custom annotation drawing must do the same.
            context.translateBy(x: -mediaOrigin.x, y: -mediaOrigin.y)
            context.concatenate(geometry.pdfToCanvas.inverted())
            UIGraphicsPushContext(context)
            image.draw(in: region)
            UIGraphicsPopContext()
            context.restoreGState()
        }
    }
}
