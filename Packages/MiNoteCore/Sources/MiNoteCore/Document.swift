import Foundation

public enum PaperStyle: String, Codable, Sendable { case blank, ruled, grid }

public struct DeletedPage: Codable, Equatable, Sendable, Identifiable {
    public var page: NotePage
    public var originalIndex: Int
    public var deletedAt: Double
    public var id: UUID { page.id }
    public init(page: NotePage, originalIndex: Int, deletedAt: Double) {
        self.page = page; self.originalIndex = originalIndex; self.deletedAt = deletedAt
    }
}

public struct NoteDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 3
    public var id: UUID
    public var revision: Int64
    public var title: String
    public var pages: [NotePage]
    public var pdfAssets: [PDFAsset]
    public var deletedPages: [DeletedPage]
    public var lastOpenedPageID: UUID?

    public init(id: UUID = UUID(), revision: Int64 = 0, title: String, pages: [NotePage],
                pdfAssets: [PDFAsset] = [], deletedPages: [DeletedPage] = [], lastOpenedPageID: UUID? = nil) {
        self.id = id; self.revision = revision; self.title = title; self.pages = pages
        self.pdfAssets = pdfAssets; self.deletedPages = deletedPages; self.lastOpenedPageID = lastOpenedPageID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, revision, title, pages, pdfAssets, deletedPages, pdfAsset, lastOpenedPageID
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id); revision = try c.decode(Int64.self, forKey: .revision)
        title = try c.decode(String.self, forKey: .title); pages = try c.decode([NotePage].self, forKey: .pages)
        lastOpenedPageID = try c.decodeIfPresent(UUID.self, forKey: .lastOpenedPageID)
        if schemaVersion <= 2 {
            pdfAssets = try c.decodeIfPresent(PDFAsset.self, forKey: .pdfAsset).map { [$0] } ?? []
            deletedPages = []
        } else {
            pdfAssets = try c.decode([PDFAsset].self, forKey: .pdfAssets)
            deletedPages = try c.decode([DeletedPage].self, forKey: .deletedPages)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(id, forKey: .id)
        try c.encode(revision, forKey: .revision); try c.encode(title, forKey: .title); try c.encode(pages, forKey: .pages)
        try c.encode(pdfAssets, forKey: .pdfAssets); try c.encode(deletedPages, forKey: .deletedPages)
        try c.encodeIfPresent(lastOpenedPageID, forKey: .lastOpenedPageID)
    }
    public static func blank() -> Self { Self(title: "나의 첫 노트", pages: [NotePage()]) }
}

public struct NotePage: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var width: Double
    public var height: Double
    public var strokes: [InkStroke]
    public var pdfSource: PDFPageSource?
    public var paper: PaperStyle
    public var isBookmarked: Bool

    public init(id: UUID = UUID(), width: Double = 595.2756, height: Double = 841.8898,
                strokes: [InkStroke] = [], pdfSource: PDFPageSource? = nil,
                paper: PaperStyle = .blank, isBookmarked: Bool = false) {
        self.id = id; self.width = width; self.height = height; self.strokes = strokes; self.pdfSource = pdfSource
        self.paper = paper; self.isBookmarked = isBookmarked
    }
    static let schemaKey = CodingUserInfoKey(rawValue: "MiNote.schemaVersion")!
    private enum CodingKeys: String, CodingKey { case id, width, height, strokes, pdfSource, paper, isBookmarked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = (decoder.userInfo[Self.schemaKey] as? Int ?? 3) <= 2
        self.init(id: try c.decode(UUID.self, forKey: .id), width: try c.decode(Double.self, forKey: .width),
                  height: try c.decode(Double.self, forKey: .height), strokes: try c.decode([InkStroke].self, forKey: .strokes),
                  pdfSource: try c.decodeIfPresent(PDFPageSource.self, forKey: .pdfSource),
                  paper: try legacy ? (c.decodeIfPresent(PaperStyle.self, forKey: .paper) ?? .blank) : c.decode(PaperStyle.self, forKey: .paper),
                  isBookmarked: try legacy ? (c.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false) : c.decode(Bool.self, forKey: .isBookmarked))
    }
}

public enum InkTool: String, Codable, Sendable { case pen, marker }

public struct InkColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
}

public struct InkTransform: Codable, Hashable, Sendable {
    public var a: Double; public var b: Double; public var c: Double
    public var d: Double; public var tx: Double; public var ty: Double
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

public struct InkPoint: Codable, Hashable, Sendable {
    public var x: Double; public var y: Double; public var timeOffset: Double
    public var width: Double; public var height: Double; public var opacity: Double
    public var force: Double; public var azimuth: Double; public var altitude: Double
    /// PencilKit's per-point secondary width scale (defaults to 1 for schema-v1 files).
    public var secondaryScale: Double
    public init(x: Double, y: Double, timeOffset: Double, width: Double, height: Double,
                opacity: Double, force: Double, azimuth: Double, altitude: Double, secondaryScale: Double = 1) {
        self.x = x; self.y = y; self.timeOffset = timeOffset; self.width = width; self.height = height
        self.opacity = opacity; self.force = force; self.azimuth = azimuth; self.altitude = altitude
        self.secondaryScale = secondaryScale
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, timeOffset, width, height, opacity, force, azimuth, altitude, secondaryScale
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try values.decode(Double.self, forKey: .x),
                  y: try values.decode(Double.self, forKey: .y),
                  timeOffset: try values.decode(Double.self, forKey: .timeOffset),
                  width: try values.decode(Double.self, forKey: .width),
                  height: try values.decode(Double.self, forKey: .height),
                  opacity: try values.decode(Double.self, forKey: .opacity),
                  force: try values.decode(Double.self, forKey: .force),
                  azimuth: try values.decode(Double.self, forKey: .azimuth),
                  altitude: try values.decode(Double.self, forKey: .altitude),
                  secondaryScale: try values.decodeIfPresent(Double.self, forKey: .secondaryScale) ?? 1)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(x, forKey: .x); try values.encode(y, forKey: .y)
        try values.encode(timeOffset, forKey: .timeOffset); try values.encode(width, forKey: .width)
        try values.encode(height, forKey: .height); try values.encode(opacity, forKey: .opacity)
        try values.encode(force, forKey: .force); try values.encode(azimuth, forKey: .azimuth)
        try values.encode(altitude, forKey: .altitude); try values.encode(secondaryScale, forKey: .secondaryScale)
    }
}

public struct InkStroke: Codable, Hashable, Sendable {
    public var id: UUID
    public var tool: InkTool
    public var color: InkColor
    public var points: [InkPoint]
    public var transform: InkTransform
    public var randomSeed: UInt32
    public var creationTime: Double
    public init(id: UUID = UUID(), tool: InkTool, color: InkColor, points: [InkPoint],
                transform: InkTransform = .identity, randomSeed: UInt32, creationTime: Double) {
        self.id = id; self.tool = tool; self.color = color; self.points = points
        self.transform = transform; self.randomSeed = randomSeed; self.creationTime = creationTime
    }
}
