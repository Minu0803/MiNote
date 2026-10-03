import Foundation

public struct PDFAsset: Codable, Equatable, Sendable {
    public let id: UUID
    public let originalFilename: String
    public let pageCount: Int
    public let byteCount: Int
    public let importedAt: Double

    public init(id: UUID = UUID(), originalFilename: String, pageCount: Int, byteCount: Int,
                importedAt: Double = Date().timeIntervalSince1970) {
        self.id = id; self.originalFilename = originalFilename; self.pageCount = pageCount
        self.byteCount = byteCount; self.importedAt = importedAt
    }
    // Derived from a UUID, never from the untrusted original file name.
    public var relativePath: String { "assets/\(id.uuidString).pdf" }
}

public struct PageRect: Codable, Equatable, Sendable {
    public let x: Double; public let y: Double; public let width: Double; public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}

public struct PDFPageSource: Codable, Equatable, Sendable {
    public var assetID: UUID?
    public let index: Int
    public let mediaBox: PageRect
    public let cropBox: PageRect
    public let rotation: Int
    public init(assetID: UUID? = nil, index: Int, mediaBox: PageRect, cropBox: PageRect, rotation: Int) {
        self.assetID = assetID; self.index = index; self.mediaBox = mediaBox; self.cropBox = cropBox; self.rotation = rotation
    }
}
