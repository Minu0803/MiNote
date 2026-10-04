import MiNoteCore
import PencilKit

/// UI framework details stay here; the document package only knows numeric values.
enum InkAdapterError: Error, LocalizedError {
    case ambiguousIdentity
    case unsupportedInk, unsupportedMask, unsupportedColor
    case unsupportedContentVersion(Int)
    case unsupportedPointAttribute(String)
    var errorDescription: String? {
        switch self {
        case .ambiguousIdentity: "겹치는 획의 ID를 확정할 수 없어 저장하지 않았습니다. 현재 필기와 기존 저장본은 유지됩니다."
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

    private struct Candidate {
        let index: Int
        let value: InkStroke
        let isCurrent: Bool
        let isRaw: Bool
    }
    static func encode(_ drawing: PKDrawing, preserving known: [InkStroke], aliases: [InkStroke] = []) throws -> [InkStroke] {
        let values = try drawing.strokes.map(portableValue)
        guard !known.isEmpty else { return values }
        let reconstructed = try decode(known).strokes.map(portableValue)
        var candidates: [InkStroke: [Candidate]] = [:]
        for index in known.indices {
            let raw = key(known[index]), restored = key(reconstructed[index])
            candidates[raw, default: []].append(Candidate(index:index,value:known[index],isCurrent:true,isRaw:true))
            if restored != raw { candidates[restored, default: []].append(Candidate(index:index,value:known[index],isCurrent:true,isRaw:false)) }
        }
        let indices=Dictionary(uniqueKeysWithValues:known.indices.map { (known[$0].id,$0) })
        for variant in aliases {
            guard let index=indices[variant.id] else { continue }
            let raw=key(variant), restored=key(try decode([variant]).strokes.map(portableValue)[0])
            candidates[raw,default:[]].append(Candidate(index:index,value:variant,isCurrent:false,isRaw:true))
            if restored != raw { candidates[restored,default:[]].append(Candidate(index:index,value:variant,isCurrent:false,isRaw:false)) }
        }
        // Supported PencilKit edits append or erase strokes without reordering
        // surviving strokes. Match the entire ordered sequence, so a raw value
        // cannot steal the provenance of another stroke's reconstruction alias.
        let options = values.map { Set((candidates[key($0)] ?? []).map(\.index)).sorted() }
        var earliest = Array<Int?>(repeating: nil, count: values.count)
        var latest = earliest
        var prior = -1
        for index in values.indices where !options[index].isEmpty {
            guard let match = options[index].first(where: { $0 > prior }) else {
                throw InkAdapterError.ambiguousIdentity
            }
            earliest[index] = match; prior = match
        }
        var following = known.count
        for index in values.indices.reversed() where !options[index].isEmpty {
            guard let match = options[index].last(where: { $0 < following }) else {
                throw InkAdapterError.ambiguousIdentity
            }
            latest[index] = match; following = match
        }
        guard earliest == latest else { throw InkAdapterError.ambiguousIdentity }
        return try values.indices.map { index in
            guard let match=earliest[index] else { return values[index] }
            let versions=(candidates[key(values[index])] ?? []).filter { $0.index == match }
            if versions.contains(where: \.isCurrent) { return known[match] }
            let raw=versions.filter(\.isRaw)
            let distinct=Set((raw.isEmpty ? versions : raw).map(\.value))
            guard distinct.count == 1, let value=distinct.first else { throw InkAdapterError.ambiguousIdentity }
            return value
        }
    }

    private static func portableValue(_ stroke: PKStroke) throws -> InkStroke {
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
        return InkStroke(tool: tool, color: InkColor(red: red, green: green, blue: blue, alpha: alpha),
            points: points, transform: InkTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty),
            randomSeed: stroke.randomSeed, creationTime: stroke.path.creationDate.timeIntervalSince1970)
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
