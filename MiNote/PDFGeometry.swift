import PDFKit

/// Canvas coordinates are the visible, rotated crop box, top-left origin, 72pt/in.
struct PDFGeometry {
    let size: CGSize
    let pdfToCanvas: CGAffineTransform

    init(page: PDFPage) throws {
        let crop = page.bounds(for: .cropBox)
        guard let reference = page.pageRef, crop.width.isFinite, crop.height.isFinite,
              crop.width > 0, crop.height > 0, [0, 90, 180, 270].contains(page.rotation) else {
            throw PDFError.invalidPage
        }
        size = page.rotation.isMultiple(of: 180) ? crop.size : CGSize(width: crop.height, height: crop.width)
        let bottomLeft = reference.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true)
        pdfToCanvas = bottomLeft.concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
    }
}

enum PDFError: Error, LocalizedError {
    case invalidPDF, locked, invalidPage, limitExceeded, missingAsset, exportFailed, busy
    var errorDescription: String? {
        switch self {
        case .invalidPDF: "PDF를 읽을 수 없습니다. 올바른 PDF 파일인지 확인해 주세요."
        case .locked: "잠긴 PDF는 지원하지 않습니다. 암호를 해제한 파일을 가져와 주세요."
        case .invalidPage: "지원하지 않는 PDF 페이지 크기 또는 회전입니다."
        case .limitExceeded: "첫 PDF 버전은 100MB, 500페이지, 한 변 2,000pt까지 지원합니다."
        case .missingAsset: "PDF 원본 자산이 없거나 저장된 페이지 정보와 다릅니다. 원본 기록은 보존됩니다."
        case .exportFailed: "PDF 출력 파일을 완성하지 못했습니다. 다시 시도해 주세요."
        case .busy: "문서 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요."
        }
    }
}
