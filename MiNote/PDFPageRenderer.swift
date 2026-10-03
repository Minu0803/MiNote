import MiNoteCore
import PDFKit
import UIKit

/// PDFKit draws rotated crop-box content in bottom-left page display space.
/// This final flip is shared by the background view and visual fixture checks.
enum PDFPageRenderer {
    static func draw(_ page: PDFPage, in context: CGContext) {
        guard let geometry = try? PDFGeometry(page: page) else { return }
        context.saveGState()
        context.translateBy(x: 0, y: geometry.size.height)
        context.scaleBy(x: 1, y: -1)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }
}

final class PDFPaperView: UIView {
    var paperStyle = PaperStyle.blank { didSet { if oldValue != paperStyle { setNeedsDisplay() } } }
    var pdfPage: PDFPage? { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        PaperRenderer.draw(paperStyle, in: context, bounds: bounds)
        if let pdfPage { PDFPageRenderer.draw(pdfPage, in: context) }
    }
}
