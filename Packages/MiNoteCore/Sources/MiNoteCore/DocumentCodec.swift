import Foundation

public enum DocumentError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidDocument(String)
    case corruptDocument
    case staleRevision
    case documentConflict

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "이 앱에서 열 수 없는 문서 버전입니다 (\(version)). 원본은 보존됩니다."
        case .invalidDocument(let reason): "문서에 지원하지 않거나 잘못된 정보가 있습니다: \(reason)"
        case .corruptDocument: "문서와 복구본을 읽을 수 없습니다. 원본 파일은 보존됩니다."
        case .staleRevision: "더 최신 내용이 이미 저장되어 있습니다."
        case .documentConflict: "다른 문서 또는 같은 버전의 다른 내용이 저장되어 있습니다."
        }
    }
}

public enum DocumentCodec {
    public static func encode(_ document: NoteDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> NoteDocument {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw DocumentError.corruptDocument
        }
        guard header.schemaVersion == 1 else { throw DocumentError.unsupportedSchema(header.schemaVersion) }
        guard let document = try? decoder.decode(NoteDocument.self, from: data) else {
            throw DocumentError.corruptDocument
        }
        try validate(document)
        return document
    }

    public static func validate(_ document: NoteDocument) throws {
        guard document.schemaVersion == 1 else { throw DocumentError.unsupportedSchema(document.schemaVersion) }
        guard document.revision >= 0, document.pages.count == 1 else {
            throw DocumentError.invalidDocument("M0-A는 한 페이지와 0 이상의 리비전을 지원합니다.")
        }
        let page = document.pages[0]
        guard page.width.isFinite, page.height.isFinite, page.width > 0, page.height > 0 else {
            throw DocumentError.invalidDocument("페이지 크기")
        }
        var ids = Set<UUID>()
        for stroke in page.strokes {
            guard ids.insert(stroke.id).inserted, !stroke.points.isEmpty, stroke.creationTime.isFinite else {
                throw DocumentError.invalidDocument("획 ID 또는 제어점")
            }
            let color = stroke.color
            guard [color.red, color.green, color.blue, color.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw DocumentError.invalidDocument("획 색상")
            }
            let t = stroke.transform
            guard [t.a, t.b, t.c, t.d, t.tx, t.ty].allSatisfy(\.isFinite), abs(t.a * t.d - t.b * t.c) > 1e-12 else {
                throw DocumentError.invalidDocument("획 변환")
            }
            var previousTime = 0.0
            for point in stroke.points {
                let values = [point.x, point.y, point.timeOffset, point.width, point.height,
                              point.opacity, point.force, point.azimuth, point.altitude]
                guard values.allSatisfy(\.isFinite), point.timeOffset >= previousTime,
                      point.width >= 0, point.height >= 0, point.force >= 0,
                      (0...1).contains(point.opacity) else {
                    throw DocumentError.invalidDocument("획 좌표 또는 속성")
                }
                previousTime = point.timeOffset
            }
        }
    }
}
