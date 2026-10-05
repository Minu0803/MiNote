import Foundation

/// Versioned interchange contains ink only, never document or PDF data.
public struct InkClipboardPayload: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var strokes: [InkStroke]
    public init(strokes: [InkStroke], schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion; self.strokes = strokes
    }
}
public struct InkClipboardBounds: Equatable, Sendable {
    public let minX: Double, minY: Double, maxX: Double, maxY: Double
    public var centerX: Double { minX / 2 + maxX / 2 }
    public var centerY: Double { minY / 2 + maxY / 2 }
}
public enum InkClipboardCodec {
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumStrokes = 2_000
    public static let maximumPoints = 100_000
    public static func encode(_ payload: InkClipboardPayload) throws -> Data {
        try validate(payload)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard data.count <= maximumBytes else { throw invalid("복사 데이터 용량 한도") }
        return data
    }
    public static func decode(_ data: Data) throws -> InkClipboardPayload {
        guard data.count <= maximumBytes else { throw invalid("붙여넣기 데이터 용량 한도") }
        // Codable intentionally tolerates unknown document fields; clipboard v1 does not.
        let value = try JSONSerialization.jsonObject(with: data)
        let root = try object(value, keys: ["schemaVersion","strokes"])
        guard let strokes = root["strokes"] as? [Any], !strokes.isEmpty, strokes.count <= maximumStrokes else { throw invalid("복사 획 수") }
        var count = 0
        for value in strokes {
            let s = try object(value, keys: ["id","tool","color","points","transform","randomSeed","creationTime"])
            _ = try object(s["color"] as Any, keys: ["red","green","blue","alpha"])
            _ = try object(s["transform"] as Any, keys: ["a","b","c","d","tx","ty"])
            guard let points = s["points"] as? [Any], points.count <= maximumPoints - count else { throw invalid("복사 제어점 수") }
            count += points.count
            for point in points {
                _ = try object(point, keys: ["x","y","timeOffset","width","height","opacity","force","azimuth","altitude","secondaryScale"])
            }
        }
        let payload = try JSONDecoder().decode(InkClipboardPayload.self, from: data)
        try validate(payload)
        return payload
    }
    static func validate(_ payload: InkClipboardPayload) throws {
        guard payload.schemaVersion == 1 else { throw DocumentError.unsupportedSchema(payload.schemaVersion) }
        guard !payload.strokes.isEmpty, payload.strokes.count <= maximumStrokes else { throw invalid("복사 획 수") }
        var count = 0
        for stroke in payload.strokes {
            guard stroke.points.count <= maximumPoints - count else { throw invalid("복사 제어점 수") }
            count += stroke.points.count
            let t = stroke.transform
            guard (t.a*t.d - t.b*t.c).isFinite else { throw invalid("복사 변환 범위") }
        }
        try DocumentCodec.validate(NoteDocument(title: "", pages: [NotePage(strokes: payload.strokes)]))
        _ = try measuredBounds(payload.strokes)
    }
    public static func bounds(of strokes: [InkStroke]) throws -> InkClipboardBounds {
        try validate(InkClipboardPayload(strokes: strokes))
        return try measuredBounds(strokes)
    }
    private static func measuredBounds(_ strokes: [InkStroke]) throws -> InkClipboardBounds {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for s in strokes {
            let t = s.transform
            for p in s.points {
                let x = t.a*p.x + t.c*p.y + t.tx, y = t.b*p.x + t.d*p.y + t.ty
                guard x.isFinite, y.isFinite else { throw invalid("복사 좌표 범위") }
                minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x); maxY = max(maxY,y)
            }
        }
        return InkClipboardBounds(minX:minX,minY:minY,maxX:maxX,maxY:maxY)
    }
    private static func object(_ value: Any, keys: Set<String>) throws -> [String:Any] {
        guard let dict = value as? [String:Any], Set(dict.keys) == keys else { throw invalid("알 수 없거나 누락된 복사 필드") }
        return dict
    }
    private static func invalid(_ message: String) -> DocumentError { .invalidDocument(message) }
}
