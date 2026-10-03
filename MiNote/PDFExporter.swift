import MiNoteCore
import PDFKit
import PencilKit
import UIKit

enum PDFExporter {
    /// Original PDF remains untouched. The returned PDF is a share/export copy.
    static func export(_ document: NoteDocument, sourceURLs: [UUID: URL], destination: URL) throws {
        try DocumentCodec.validate(document)
        let outputPath = destination.standardizedFileURL.resolvingSymlinksInPath()
        var sourcePaths = Set<URL>()
        for asset in document.pdfAssets {
            guard let url = sourceURLs[asset.id] else { throw PDFError.missingAsset }
            let path = url.standardizedFileURL.resolvingSymlinksInPath()
            guard path != outputPath, sourcePaths.insert(path).inserted else { throw PDFError.exportFailed }
            _ = try PDFValidation.open(url: url, asset: asset,
                referencedPages: (document.pages + document.deletedPages.map(\.page)).filter { $0.pdfSource?.assetID == asset.id })
        }
        let output = PDFDocument()
        var cachedID: UUID?
        var cachedPDF: PDFDocument?
        for (index, model) in document.pages.enumerated() {
            let page: PDFPage
            if let reference = model.pdfSource {
                guard let assetID = reference.assetID, let url = sourceURLs[assetID],
                      let asset = document.pdfAssets.first(where: { $0.id == assetID }) else { throw PDFError.missingAsset }
                if cachedID != assetID {
                    cachedPDF = try PDFValidation.open(url: url, asset: asset,
                        referencedPages: document.pages.filter { $0.pdfSource?.assetID == assetID })
                    cachedID = assetID
                }
                // Copy before adding ink: duplicates must never mutate their shared source page.
                guard let original = cachedPDF?.page(at: reference.index), let independent = original.copy() as? PDFPage else {
                    throw PDFError.exportFailed
                }
                page = independent
            } else {
                let bounds = CGRect(x: 0, y: 0, width: model.width, height: model.height)
                let renderer = UIGraphicsPDFRenderer(bounds: bounds)
                let bytes = renderer.pdfData { context in
                    context.beginPage()
                    PaperRenderer.draw(model.paper, in: context.cgContext, bounds: bounds)
                }
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
