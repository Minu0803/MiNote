import Foundation

public enum DocumentError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidDocument(String)
    case corruptDocument
    case staleRevision
    case documentConflict
    case missingAsset

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "이 앱에서 열 수 없는 문서 버전입니다 (\(version)). 원본은 보존됩니다."
        case .invalidDocument(let reason): "문서에 지원하지 않거나 잘못된 정보가 있습니다: \(reason)"
        case .corruptDocument: "문서와 복구본을 읽을 수 없습니다. 원본 파일은 보존됩니다."
        case .staleRevision: "더 최신 내용이 이미 저장되어 있습니다."
        case .missingAsset: "PDF 원본 자산이 없거나 손상되었습니다. 기록은 보존됩니다."
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
        guard (1...3).contains(header.schemaVersion) else { throw DocumentError.unsupportedSchema(header.schemaVersion) }
        guard var document = try? decoder.decode(NoteDocument.self, from: data) else {
            throw DocumentError.corruptDocument
        }
        if header.schemaVersion <= 2 {
            try validateLegacy(document)
            document.schemaVersion = 3
            for i in document.pages.indices {
                if var source = document.pages[i].pdfSource {
                    source.assetID = document.pdfAssets.first?.id; document.pages[i].pdfSource = source
                }
                document.pages[i].paper = .blank; document.pages[i].isBookmarked = false
            }
        }
        try validate(document)
        return document
    }

    public static let maximumPages = 1_000
    public static let maximumAssetBytes = 500 * 1024 * 1024

    private static func validateLegacy(_ document: NoteDocument) throws {
        if document.schemaVersion == 1 {
            guard document.pages.count == 1, document.pdfAssets.isEmpty, document.pages[0].pdfSource == nil else {
                throw DocumentError.invalidDocument("v1 페이지 수")
            }
        }
        var indices = Set<Int>()
        for page in document.pages {
            if let source = page.pdfSource {
                guard let asset = document.pdfAssets.first, source.index >= 0, source.index < asset.pageCount,
                      indices.insert(source.index).inserted else { throw DocumentError.invalidDocument("legacy PDF 매핑") }
            }
        }
        guard indices.count == (document.pdfAssets.first?.pageCount ?? 0) else {
            throw DocumentError.invalidDocument("legacy PDF 페이지 누락")
        }
    }

    public static func validate(_ document: NoteDocument) throws {
        guard document.schemaVersion == 3 else { throw DocumentError.unsupportedSchema(document.schemaVersion) }
        guard document.revision >= 0, !document.pages.isEmpty,
              document.pages.count + document.deletedPages.count <= maximumPages else {
            throw DocumentError.invalidDocument("페이지 수 또는 리비전")
        }
        if let selected = document.lastOpenedPageID, !document.pages.contains(where: { $0.id == selected }) {
            throw DocumentError.invalidDocument("마지막 페이지 ID")
        }
        var ids: Set<UUID> = [document.id]
        var assets: [UUID: PDFAsset] = [:]
        var totalBytes = 0
        for asset in document.pdfAssets {
            guard ids.insert(asset.id).inserted, (1...500).contains(asset.pageCount),
                  asset.byteCount > 0, asset.byteCount <= 100 * 1024 * 1024,
                  asset.byteCount <= maximumAssetBytes - totalBytes,
                  !asset.originalFilename.isEmpty, asset.importedAt.isFinite else {
                throw DocumentError.invalidDocument("PDF 자산 또는 용량 제한")
            }
            totalBytes += asset.byteCount; assets[asset.id] = asset
        }
        for deleted in document.deletedPages {
            guard (0..<maximumPages).contains(deleted.originalIndex), deleted.deletedAt.isFinite, deleted.deletedAt >= 0 else {
                throw DocumentError.invalidDocument("삭제 페이지 기록")
            }
        }
        for page in document.pages + document.deletedPages.map(\.page) {
            guard ids.insert(page.id).inserted else { throw DocumentError.invalidDocument("페이지 ID") }
            guard page.width.isFinite, page.height.isFinite, page.width > 0, page.height > 0 else {
                throw DocumentError.invalidDocument("페이지 크기")
            }
            if let source = page.pdfSource {
                guard let assetID = source.assetID, let asset = assets[assetID],
                      source.index >= 0, source.index < asset.pageCount, source.mediaBox.isValid, source.cropBox.isValid,
                      [0, 90, 180, 270].contains(source.rotation), page.paper == .blank,
                      max(page.width, page.height) <= 2_000 else {
                    throw DocumentError.invalidDocument("PDF 페이지 매핑")
                }
                let rotated = source.rotation == 90 || source.rotation == 270
                let width = rotated ? source.cropBox.height : source.cropBox.width
                let height = rotated ? source.cropBox.width : source.cropBox.height
                guard abs(page.width - width) < 0.001, abs(page.height - height) < 0.001 else {
                    throw DocumentError.invalidDocument("PDF 페이지 크기")
                }
            }
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
                                  point.opacity, point.force, point.azimuth, point.altitude, point.secondaryScale]
                    guard values.allSatisfy(\.isFinite), point.timeOffset >= previousTime,
                          point.width >= 0, point.height >= 0, point.force >= 0, point.secondaryScale >= 0,
                          (0...1).contains(point.opacity) else {
                        throw DocumentError.invalidDocument("획 좌표 또는 속성")
                    }
                    previousTime = point.timeOffset
                }
            }
        }
    }
}
