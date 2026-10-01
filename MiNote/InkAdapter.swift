import MiNoteCore
import PencilKit

/// UI framework details stay here; the document package only knows numeric values.
enum InkAdapterError: Error, LocalizedError {
    case unsupportedInk, unsupportedMask, unsupportedColor
    case unsupportedContentVersion(Int)
    case unsupportedPointAttribute(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedInk: "현재는 펜과 형광펜만 저장할 수 있습니다."
        case .unsupportedMask: "부분 지우개로 편집한 획은 아직 지원하지 않습니다."
        case .unsupportedContentVersion(let version): "PencilKit 콘텐츠 버전 \(version)은 지원하지 않습니다."
        case .unsupportedPointAttribute(let attribute): "현재 문서 형식에서 지원하지 않는 필기 정보입니다 (\(attribute))."
        case .unsupportedColor: "저장할 수 없는 색상입니다."
        }
    }
}

enum InkAdapter {
    private static let contentID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))

    static func encode(_ drawing: PKDrawing, preserving known: [InkStroke]) throws -> [InkStroke] {
        var identities: [InkStroke: [UUID]] = [:]
        for stroke in known.reversed() {
            identities[key(stroke), default: []].append(stroke.id)
        }
        return try drawing.strokes.map { stroke in
            guard stroke.requiredContentVersion == .version1 else { throw InkAdapterError.unsupportedContentVersion(stroke.requiredContentVersion.rawValue) }
            guard stroke.mask == nil else { throw InkAdapterError.unsupportedMask }
            let tool: InkTool
            switch stroke.ink.inkType {
            case .pen: tool = .pen
            case .marker: tool = .marker
            default: throw InkAdapterError.unsupportedInk
            }
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                throw InkAdapterError.unsupportedColor
            }
            let points = try stroke.path.map { point -> InkPoint in
                let ordinary = PKStrokePoint(location: point.location, timeOffset: point.timeOffset,
                    size: point.size, opacity: point.opacity, force: point.force,
                    azimuth: point.azimuth, altitude: point.altitude)
                if #available(iOS 26, *), point.threshold != ordinary.threshold { throw InkAdapterError.unsupportedPointAttribute("threshold") }
                if #available(iOS 27, *), point.lateralJitter != ordinary.lateralJitter { throw InkAdapterError.unsupportedPointAttribute("lateralJitter") }
                return InkPoint(x: point.location.x, y: point.location.y, timeOffset: point.timeOffset,
                    width: point.size.width, height: point.size.height, opacity: point.opacity,
                    force: point.force, azimuth: point.azimuth, altitude: point.altitude,
                    secondaryScale: point.secondaryScale)
            }
            let t = stroke.transform
            var value = InkStroke(tool: tool, color: InkColor(red: red, green: green, blue: blue, alpha: alpha),
                points: points, transform: InkTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty),
                randomSeed: stroke.randomSeed, creationTime: stroke.path.creationDate.timeIntervalSince1970)
            let fingerprint = key(value)
            if let id = identities[fingerprint]?.popLast() { value.id = id }
            return value
        }
    }

    static func decode(_ strokes: [InkStroke]) throws -> PKDrawing {
        try DocumentCodec.validate(NoteDocument(title: "", pages: [NotePage(strokes: strokes)]))
        return PKDrawing(strokes: strokes.map { stroke in
            let points = stroke.points.map { point in
                PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: point.timeOffset,
                    size: CGSize(width: point.width, height: point.height), opacity: point.opacity,
                    force: point.force, azimuth: point.azimuth, altitude: point.altitude,
                    secondaryScale: point.secondaryScale)
            }
            let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: stroke.creationTime))
            let c = stroke.color, t = stroke.transform
            return PKStroke(ink: PKInk(stroke.tool == .pen ? .pen : .marker,
                    color: UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)),
                path: path, transform: CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty),
                mask: nil, randomSeed: stroke.randomSeed)
        })
    }

    private static func key(_ stroke: InkStroke) -> InkStroke {
        var value = stroke
        value.id = contentID
        return value
    }
}
