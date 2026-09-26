import Foundation

public struct NoteDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var id: UUID
    public var revision: Int64
    public var title: String
    public var pages: [NotePage]

    public init(id: UUID = UUID(), revision: Int64 = 0, title: String, pages: [NotePage]) {
        self.id = id; self.revision = revision; self.title = title; self.pages = pages
    }

    public static func blank() -> Self {
        Self(title: "나의 첫 노트", pages: [NotePage()])
    }
}

public struct NotePage: Codable, Equatable, Sendable {
    public var id: UUID
    public var width: Double
    public var height: Double
    public var strokes: [InkStroke]

    public init(id: UUID = UUID(), width: Double = 595.2756, height: Double = 841.8898,
                strokes: [InkStroke] = []) {
        self.id = id; self.width = width; self.height = height; self.strokes = strokes
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
