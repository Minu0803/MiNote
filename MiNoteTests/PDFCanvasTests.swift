import PDFKit
import UIKit
import XCTest
@testable import MiNote

@MainActor final class PDFCanvasTests: XCTestCase {
    func testRenderedSourceCornersAlignWithCanvasForEveryRotation() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: PDFFixture.data()))
        let greenCenters = [CGPoint(x: 10, y: 10), CGPoint(x: 440, y: 10),
                            CGPoint(x: 290, y: 440), CGPoint(x: 10, y: 290)]
        let redCenters = [CGPoint(x: 10, y: 440), CGPoint(x: 10, y: 10),
                          CGPoint(x: 290, y: 10), CGPoint(x: 440, y: 290)]
        for index in 0..<4 {
            let page = try XCTUnwrap(pdf.page(at: index))
            let size = try PDFGeometry(page: page).size
            let image = renderPDFPage(page, size: size)
            let green = pixel(image, at: greenCenters[index])
            let red = pixel(image, at: redCenters[index])
            XCTAssertGreaterThan(green[1], 200, "Green corner rotation \(index * 90)")
            XCTAssertLessThan(green[0], 30)
            XCTAssertGreaterThan(red[0], 200, "Red corner rotation \(index * 90)")
            XCTAssertLessThan(red[1], 30)
        }
    }

    func testZoomAndViewportResizeKeepDocumentBounds() throws {
        let host = PageZoomHost(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        let page = try XCTUnwrap(PDFDocument(data: PDFFixture.data()).flatMap { $0.page(at: 1) })
        host.configurePage(size: CGSize(width: 450, height: 300), pdfPage: page)
        host.layoutIfNeeded()
        let scroll = try XCTUnwrap(host.subviews.first as? UIScrollView)
        scroll.zoomScale = 2.4
        host.frame.size = CGSize(width: 600, height: 800)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        XCTAssertEqual(host.canvas.bounds.size, CGSize(width: 450, height: 300))
        XCTAssertEqual(scroll.contentSize.width, 450 * scroll.zoomScale, accuracy: 0.01)
        XCTAssertEqual(scroll.contentSize.height, 300 * scroll.zoomScale, accuracy: 0.01)
    }
}

@MainActor func renderPDFPage(_ page: PDFPage, size: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { output in
        UIColor.white.setFill(); output.fill(CGRect(origin: .zero, size: size))
        PDFPageRenderer.draw(page, in: output.cgContext)
    }
}

func pixel(_ image: UIImage, at point: CGPoint) -> [UInt8] {
    let cgImage = image.cgImage!
    var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
    bytes.withUnsafeMutableBytes { storage in
        let context = CGContext(data: storage.baseAddress, width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    }
    let index = (Int(point.y) * cgImage.width + Int(point.x)) * 4
    return Array(bytes[index..<index + 4])
}
