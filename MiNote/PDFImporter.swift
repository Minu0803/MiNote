import Foundation
import MiNoteCore
import PDFKit

struct PreparedPDF: Sendable {
    let data: Data
    let asset: PDFAsset
    let pages: [NotePage]
}

/// File coordination and parsing run off the editor's main actor. PDFKit objects
/// stay within this actor; only portable metadata and immutable bytes cross it.
actor PDFImporter {
    func prepare(url: URL) throws -> PreparedPDF {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<PreparedPDF, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= PDFValidation.maximumBytes else { throw PDFError.limitExceeded }
                return try prepareBytes(Data(contentsOf: coordinated), filename: url.lastPathComponent)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw PDFError.invalidPDF }
        return try result.get()
    }

    func prepare(data: Data, filename: String) throws -> PreparedPDF {
        try prepareBytes(data, filename: filename)
    }

    private func prepareBytes(_ data: Data, filename: String) throws -> PreparedPDF {
        guard data.count <= PDFValidation.maximumBytes else { throw PDFError.limitExceeded }
        guard data.starts(with: Data("%PDF-".utf8)),
              data.suffix(1024).range(of: Data("%%EOF".utf8)) != nil,
              let document = PDFDocument(data: data) else { throw PDFError.invalidPDF }
        let pages = try PDFValidation.pages(of: document)
        return PreparedPDF(data: data,
            asset: PDFAsset(originalFilename: filename, pageCount: pages.count, byteCount: data.count), pages: pages)
    }
}

enum PDFValidation {
    static let maximumBytes = 100 * 1024 * 1024
    static func pages(of document: PDFDocument) throws -> [NotePage] {
        guard !document.isLocked else { throw PDFError.locked }
        guard document.pageCount > 0 else { throw PDFError.invalidPDF }
        guard document.pageCount <= 500 else { throw PDFError.limitExceeded }
        return try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { throw PDFError.invalidPage }
            let geometry = try PDFGeometry(page: page)
            guard max(geometry.size.width, geometry.size.height) <= 2_000 else { throw PDFError.limitExceeded }
            return NotePage(width: geometry.size.width, height: geometry.size.height,
                pdfSource: PDFPageSource(index: index, mediaBox: rect(page.bounds(for: .mediaBox)),
                                        cropBox: rect(page.bounds(for: .cropBox)), rotation: page.rotation))
        }
    }
    static func rect(_ box: CGRect) -> PageRect { PageRect(x: box.minX, y: box.minY, width: box.width, height: box.height) }

    static func open(url: URL, for document: NoteDocument) throws -> PDFDocument {
        guard let asset = document.pdfAsset, let pdf = PDFDocument(url: url) else { throw PDFError.missingAsset }
        let pages = try pages(of: pdf).map { page in
            var page = page
            if var source = page.pdfSource { source.assetID = asset.id; page.pdfSource = source }
            return page
        }
        guard pages.count == asset.pageCount,
              document.pages.compactMap(\.pdfSource).sorted(by: { $0.index < $1.index }) == pages.compactMap(\.pdfSource) else {
            throw PDFError.missingAsset
        }
        return pdf
    }
}
