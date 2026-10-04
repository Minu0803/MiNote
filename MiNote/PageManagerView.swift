import MiNoteCore
import SwiftUI

struct PageManagerView: View {
    @ObservedObject var session: EditorSession
    let onClose: () -> Void
    @State private var filter = Filter.all
    @State private var deleting: UUID?
    @State private var purging: UUID?
    private enum Filter: CaseIterable {
        case all, bookmarked, deleted
        var title: String { switch self { case .all: "전체"; case .bookmarked: "책갈피"; case .deleted: "삭제됨" } }
        var identifier: String { switch self { case .all: "all"; case .bookmarked: "bookmarked"; case .deleted: "deleted" } }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    ForEach(Filter.allCases, id: \.self) { value in
                        Button(value.title) { filter = value }
                            .buttonStyle(.bordered).tint(filter == value ? .blue : .gray)
                            .accessibilityIdentifier("filter-pages-\(value.identifier)")
                    }
                    Spacer()
                    Menu {
                        ForEach([PaperStyle.blank, .ruled, .grid], id: \.self) { paper in
                            Button(paper.title) {
                                if let id = session.currentPage?.id { run(.insert(after: id, paper: paper)) }
                                filter = .all
                            }.accessibilityIdentifier("addPage-\(paper.rawValue)")
                        }
                    } label: { Label("페이지 추가", systemImage: "plus") }
                    .accessibilityIdentifier("addPage").disabled(session.isProcessing)
                }.padding()
                if let error = session.operationError {
                    HStack {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Spacer()
                        Button("확인") { session.operationError = nil }
                    }.padding().background(Color.red.opacity(0.06))
                }
                List {
                    if let document = session.document {
                        if filter == .deleted {
                            ForEach(document.deletedPages) { deleted in
                                HStack(spacing: 16) {
                                    thumbnail(deleted.page, revision: document.revision)
                                    VStack(alignment: .leading) {
                                        Text("삭제한 페이지").font(.headline)
                                        Text("\(deleted.page.strokes.count)획 · \(deleted.page.pdfSource == nil ? deleted.page.paper.title : "PDF")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("복원") { run(.restore(deleted.id)) }
                                        .buttonStyle(.bordered).accessibilityIdentifier("restorePage-\(deleted.id)")
                                    Button("영구 삭제", role: .destructive) { purging = deleted.id }
                                        .buttonStyle(.bordered).accessibilityIdentifier("purgePage-\(deleted.id)")
                                }.disabled(session.isProcessing)
                            }
                            if document.deletedPages.isEmpty { Text("삭제한 페이지가 없습니다.").foregroundStyle(.secondary) }
                        } else {
                            let pages = document.pages.filter { filter != .bookmarked || $0.isBookmarked }
                            ForEach(pages) { page in
                                if let index = document.pages.firstIndex(where: { $0.id == page.id }) {
                                    row(page, index: index, document: document)
                                        .moveDisabled(filter != .all || session.isProcessing)
                                }
                            }
                            .onMove { source, destination in
                                guard filter == .all, source.count == 1, let from = source.first else { return }
                                let target = destination > from ? destination - 1 : destination
                                run(.move(document.pages[from].id, toIndex: target))
                            }
                            if pages.isEmpty { Text("책갈피를 표시한 페이지가 없습니다.").foregroundStyle(.secondary) }
                        }
                    }
                }.listStyle(.plain)
                Text("삭제한 페이지는 이 노트에서 복원할 수 있습니다.")
                    .font(.footnote).foregroundStyle(.secondary).padding()
            }
            .navigationTitle("페이지 관리")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton().disabled(filter != .all || session.isProcessing) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료", action: onClose).accessibilityIdentifier("closePageManager").disabled(session.isProcessing)
                }
            }
            .alert("페이지를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("취소", role: .cancel) { deleting = nil }
                Button("삭제", role: .destructive) {
                    if let id = deleting { run(.delete(id)) }; deleting = nil
                }.accessibilityIdentifier("confirmDeletePage")
            } message: { Text("필기와 PDF 참조를 보관하며 삭제됨 목록에서 복원할 수 있습니다.") }
            .alert("보관 페이지를 영구 삭제할까요?", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } })) {
                Button("취소", role: .cancel) { purging = nil }
                Button("영구 삭제", role: .destructive) { if let id = purging { Task { await session.purgeDeletedPage(id) } }; purging = nil }
                    .accessibilityIdentifier("confirmPurgePage")
            } message: { Text("이 페이지의 필기를 삭제 보관 목록에서 제거합니다. 되돌릴 수 없습니다. 이전 정상 복구본에서 사용하는 PDF는 정리하지 않습니다.") }
        }
        .interactiveDismissDisabled(session.isProcessing)
    }
    private func row(_ page: NotePage, index: Int, document: NoteDocument) -> some View {
        HStack(spacing: 16) {
            Button {
                Task { await session.selectPage(index) }
            } label: {
                HStack(spacing: 16) {
                    thumbnail(page, revision: document.revision)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("페이지 \(index + 1)").font(.headline)
                            if page.isBookmarked { Image(systemName: "bookmark.fill") }
                            if session.currentPage?.id == page.id { Image(systemName: "checkmark.circle.fill") }
                        }
                        Text("\(page.pdfSource == nil ? page.paper.title : "PDF") · \(page.strokes.count)획")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("selectPage-\(index + 1)")
            Menu {
                Button("복제") { run(.duplicate(page.id)) }.accessibilityIdentifier("duplicatePage")
                Button(page.isBookmarked ? "책갈피 해제" : "책갈피 표시") { run(.setBookmark(page.id, !page.isBookmarked)) }
                    .accessibilityIdentifier("bookmarkPage")
                if page.pdfSource == nil {
                    Menu("용지 변경") {
                        ForEach([PaperStyle.blank, .ruled, .grid], id: \.self) { style in
                            Button(style.title) { run(.setPaper(page.id, style)) }.accessibilityIdentifier("setPaper-\(style.rawValue)")
                        }
                    }
                }
                Button("앞으로 이동") { run(.move(page.id, toIndex: index - 1)) }
                    .disabled(index == 0).accessibilityIdentifier("movePageUp")
                Button("뒤로 이동") { run(.move(page.id, toIndex: index + 1)) }
                    .disabled(index + 1 == document.pages.count).accessibilityIdentifier("movePageDown")
                Button("삭제", role: .destructive) { deleting = page.id }
                    .disabled(document.pages.count == 1).accessibilityIdentifier("deletePage")
            } label: { Image(systemName: "ellipsis.circle").font(.title2).padding(8) }
            .accessibilityLabel("페이지 \(index + 1) 작업").accessibilityIdentifier("pageActions-\(index + 1)")
        }
        .disabled(session.isProcessing)
        .padding(.vertical, 4)
    }
    private func thumbnail(_ page: NotePage, revision: Int64) -> some View {
        PageThumbnailView(session: session, pageID: page.id, revision: revision)
    }
    private func run(_ command: PageCommand) { Task { await session.applyPageCommand(command) } }
}

private struct PageThumbnailView: View {
    @ObservedObject var session: EditorSession
    let pageID: UUID
    let revision: Int64
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "doc").foregroundStyle(.secondary) }
        }
        .frame(width: 64, height: 80).background(.white)
        .overlay(Rectangle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        .accessibilityHidden(true)
        .task(id: revision) {
            image = nil
            let rendered = await session.thumbnail(pageID: pageID, expectedRevision: revision)
            guard !Task.isCancelled, session.document?.revision == revision else { return }
            image = rendered
        }
    }
}
