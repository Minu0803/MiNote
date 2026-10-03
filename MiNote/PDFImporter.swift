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
        var pages = try PDFValidation.pages(of: document)
        let asset = PDFAsset(originalFilename: filename, pageCount: pages.count, byteCount: data.count)
        for i in pages.indices {
            if var source = pages[i].pdfSource { source.assetID = asset.id; pages[i].pdfSource = source }
        }
        return PreparedPDF(data: data, asset: asset, pages: pages)
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

    static func open(url: URL, asset: PDFAsset, referencedPages: [NotePage]) throws -> PDFDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, size.fileSize == asset.byteCount,
              let pdf = PDFDocument(url: url) else { throw PDFError.missingAsset }
        let originals = try pages(of: pdf)
        guard originals.count == asset.pageCount else { throw PDFError.missingAsset }
        for model in referencedPages {
            guard let source = model.pdfSource, source.assetID == asset.id,
                  originals.indices.contains(source.index), var expected = originals[source.index].pdfSource else {
                throw PDFError.missingAsset
            }
            expected.assetID = asset.id
            guard source == expected else { throw PDFError.missingAsset }
        }
        return pdf
    }

    // Temporary Task 1/3 call bridge, removed when EditorSession becomes asset-specific.
    static func open(url: URL, for document: NoteDocument) throws -> PDFDocument {
        guard let asset = document.pdfAssets.first else { throw PDFError.missingAsset }
        return try open(url: url, asset: asset,
                        referencedPages: document.pages.filter { $0.pdfSource?.assetID == asset.id })
    }
}
