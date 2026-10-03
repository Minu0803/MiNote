import MiNoteCore
import UIKit

/// Context uses document points and a top-left origin in every rendering surface.
enum PaperRenderer {
    static let spacing: CGFloat = 24
    static let lineWidth: CGFloat = 0.5
    static func draw(_ style: PaperStyle, in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.setFillColor(UIColor.white.cgColor); context.fill(bounds)
        guard style != .blank else { context.restoreGState(); return }
        context.clip(to: bounds)
        context.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
        context.setLineWidth(lineWidth)
        for y in stride(from: bounds.minY + spacing, to: bounds.maxY, by: spacing) {
            context.move(to: CGPoint(x: bounds.minX, y: y)); context.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        if style == .grid {
            for x in stride(from: bounds.minX + spacing, to: bounds.maxX, by: spacing) {
                context.move(to: CGPoint(x: x, y: bounds.minY)); context.addLine(to: CGPoint(x: x, y: bounds.maxY))
            }
        }
        context.strokePath(); context.restoreGState()
    }
}
