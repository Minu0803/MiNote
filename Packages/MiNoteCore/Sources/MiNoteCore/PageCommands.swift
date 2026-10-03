import Foundation

public enum PageCommand: Equatable, Sendable {
    case insert(after: UUID, paper: PaperStyle)
    case duplicate(UUID)
    case move(UUID, toIndex: Int)
    case delete(UUID)
    case restore(UUID)
    case setPaper(UUID, PaperStyle)
    case setBookmark(UUID, Bool)
}

/// Value commands either return a fully valid document or leave their input intact.
public enum PageCommands {
    public static func apply(_ command: PageCommand, to document: NoteDocument) throws -> NoteDocument {
        try DocumentCodec.validate(document)
        guard document.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
        var result = document
        func index(_ id: UUID) throws -> Int {
            guard let index = result.pages.firstIndex(where: { $0.id == id }) else {
                throw DocumentError.invalidDocument("페이지를 찾을 수 없습니다.")
            }
            return index
        }
        switch command {
        case .insert(let after, let paper):
            let at = try index(after)
            let page = NotePage(paper: paper)
            result.pages.insert(page, at: at + 1); result.lastOpenedPageID = page.id
        case .duplicate(let id):
            let at = try index(id)
            var page = result.pages[at]; page.id = UUID(); page.isBookmarked = false
            for i in page.strokes.indices { page.strokes[i].id = UUID() }
            result.pages.insert(page, at: at + 1); result.lastOpenedPageID = page.id
        case .move(let id, let destination):
            let at = try index(id)
            guard result.pages.indices.contains(destination) else { throw DocumentError.invalidDocument("페이지 순서 범위") }
            let page = result.pages.remove(at: at); result.pages.insert(page, at: destination)
        case .delete(let id):
            let at = try index(id)
            guard result.pages.count > 1 else { throw DocumentError.invalidDocument("마지막 페이지는 삭제할 수 없습니다.") }
            let selected = result.lastOpenedPageID ?? result.pages[0].id
            let page = result.pages.remove(at: at)
            result.deletedPages.append(DeletedPage(page: page, originalIndex: at, deletedAt: Date().timeIntervalSince1970))
            if selected == id { result.lastOpenedPageID = result.pages[min(at, result.pages.count - 1)].id }
        case .restore(let id):
            guard let at = result.deletedPages.firstIndex(where: { $0.id == id }) else {
                throw DocumentError.invalidDocument("삭제 페이지를 찾을 수 없습니다.")
            }
            let deleted = result.deletedPages.remove(at: at)
            result.pages.insert(deleted.page, at: min(deleted.originalIndex, result.pages.count))
            result.lastOpenedPageID = id
        case .setPaper(let id, let paper):
            let at = try index(id)
            guard result.pages[at].pdfSource == nil else { throw DocumentError.invalidDocument("PDF 용지는 변경할 수 없습니다.") }
            result.pages[at].paper = paper
        case .setBookmark(let id, let value):
            result.pages[try index(id)].isBookmarked = value
        }
        result.revision += 1
        try DocumentCodec.validate(result)
        return result
    }
}
