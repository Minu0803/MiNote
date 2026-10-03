import MiNoteCore
import PDFKit
import PencilKit
import UIKit

@MainActor enum PageThumbnailRenderer {
    static func image(for page: NotePage, pdfPage: PDFPage?, maximumPixelEdge: Int = 256) throws -> UIImage {
        guard (1...256).contains(maximumPixelEdge), page.width > 0, page.height > 0 else { throw PDFError.invalidPage }
        if page.pdfSource != nil, pdfPage == nil { throw PDFError.missingAsset }
        let scale = CGFloat(maximumPixelEdge) / max(page.width, page.height)
        let size = CGSize(width: max(1, floor(page.width * scale)), height: max(1, floor(page.height * scale)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let drawing = try InkAdapter.decode(page.strokes)
        let bounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let context = output.cgContext
            context.scaleBy(x: size.width / page.width, y: size.height / page.height)
            PaperRenderer.draw(page.paper, in: context, bounds: bounds)
            if let pdfPage { PDFPageRenderer.draw(pdfPage, in: context) }
            if !drawing.strokes.isEmpty { drawing.image(from: bounds, scale: scale).draw(in: bounds) }
        }
    }
}
