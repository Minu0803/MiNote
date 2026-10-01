import PDFKit
import UIKit

@MainActor enum PDFFixture {
    static let media = CGRect(x: 10, y: 20, width: 400, height: 600)
    static let crop = CGRect(x: 40, y: 70, width: 300, height: 450)

    /// Raw PDF deliberately avoids PDFKit rewriting/normalizing nonzero box origins.
    static func data(rotations: [Int] = [0, 90, 180, 270]) throws -> Data {
        let children = rotations.indices.map { "\(4 + $0 * 2) 0 R" }.joined(separator: " ")
        var objects = ["<< /Type /Catalog /Pages 2 0 R >>",
                       "<< /Type /Pages /Kids [\(children)] /Count \(rotations.count) >>",
                       "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
        let linkID = 4 + rotations.count * 2
        let stream = "1 1 1 rg 10 20 400 600 re f\n1 0 0 rg 40 70 20 20 re f\n0 1 0 rg 40 500 20 20 re f\n0 0 0 rg BT /F1 16 Tf 100 200 Td (MiNote PDF fixture) Tj ET\n"
        for (index, rotation) in rotations.enumerated() {
            let annotation = index == 0 ? "/Annots [\(linkID) 0 R]" : ""
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [10 20 410 620] /CropBox [40 70 340 520] /Rotate \(rotation) /Resources << /Font << /F1 3 0 R >> >> /Contents \(5 + index * 2) 0 R \(annotation) >>")
            objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream")
        }
        objects.append("<< /Type /Annot /Subtype /Link /Rect [100 300 180 320] /Border [0 0 0] /A << /S /URI /URI (https://example.com/minote) >> >>")
        var result = "%PDF-1.7\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(result.utf8.count)
            result += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = result.utf8.count
        result += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { result += String(format: "%010d 00000 n \n", offset) }
        result += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(result.utf8)
    }
}
