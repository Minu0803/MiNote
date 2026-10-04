import MiNoteCore
import SwiftUI

struct LibraryView: View {
    @ObservedObject var session: LibrarySession
    @State private var filter: LibraryFilter = .all
    @State private var nameRequest: NameRequest?
    @State private var moveRequest: MoveRequest?
    @State private var name = ""
    @State private var showsBackupImporter = false
    @State private var showsMaintenance = false
    @State private var purging: LibraryNoteRow?

    var body: some View {
        Group {
            if let editor = session.selectedEditor {
                NoteEditorView(session: editor, onClose: { Task { await session.closeNote() } })
                    .id(editor.document?.id)
                    .disabled(session.isBusy).allowsHitTesting(!session.isBusy)
            } else if let error = session.loadError {
                ContentUnavailableView {
                    Label("라이브러리를 열 수 없습니다", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("다시 시도") { Task { await session.load() } }.accessibilityIdentifier("retryLibrary")
                }
            } else {
                library
            }
        }
        .overlay {
            if session.isBusy {
                BackupProgressView(progress: session.operationProgress,
                    cancel: session.isRestoringBackup ? { session.cancelBackupRestore() } : nil)
            }
        }
        .task { await session.load() }
        .sheet(item: $nameRequest) { request in nameSheet(request) }
        .sheet(item: $moveRequest) { request in moveSheet(request) }
        .sheet(isPresented: $showsMaintenance) { StorageMaintenanceView(session: session) { showsMaintenance = false } }
        .alert("노트를 영구 삭제할까요?", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } })) {
            Button("취소", role: .cancel) { purging = nil }
            Button("영구 삭제", role: .destructive) { if let row = purging { Task { await session.purgeNote(row.id) } }; purging = nil }
                .accessibilityIdentifier("confirmPurgeNote")
        } message: { Text("\(purging?.title ?? "노트")의 필기·PDF·삭제 보관 페이지를 제거합니다. 이 작업은 되돌릴 수 없습니다.") }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(
            get: { session.operationError != nil && !showsMaintenance }, set: { if !$0 { session.operationError = nil } })) {
                Button("확인") { session.operationError = nil }
            } message: { Text(session.operationError ?? "") }
        .preferredColorScheme(.light)
    }

    private var library: some View {
        NavigationStack {
          HStack(spacing: 0) {
            List {
                filterButton(.all, name: "모든 노트", symbol: "books.vertical", id: "filter-all")
                filterButton(.recent, name: "최근 노트", symbol: "clock", id: "filter-recent")
                filterButton(.trash, name: "휴지통", symbol: "trash", id: "filter-trash")
                Section("폴더") {
                    ForEach(sortedFolders) { folder in
                        HStack {
                            Button { filter = .folder(folder.id) } label: {
                                Label(folderPath(folder.id), systemImage: "folder")
                                    .foregroundStyle(filter == .folder(folder.id) ? Color.accentColor : .primary)
                            }.accessibilityLabel(folderPath(folder.id)).accessibilityIdentifier("folder-\(folder.id)")
                            Spacer()
                            Menu {
                                Button("이름 변경") { requestName(.renameFolder(folder.id), initial: folder.name) }.accessibilityIdentifier("renameFolder")
                                Button("폴더 이동") { moveRequest = MoveRequest(kind: .folder, target: folder.id) }.accessibilityIdentifier("moveFolder")
                            } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("폴더 관리 \(folderPath(folder.id))")
                        }
                    }
                }
            }
            .listStyle(.sidebar).frame(width: 228).accessibilityIdentifier("libraryFolders")
            Divider()
            VStack(spacing: 0) {
                if let notice = session.recoveryNotice {
                    Label(notice, systemImage: "arrow.uturn.backward.circle")
                        .font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12)).accessibilityIdentifier("libraryRecovery")
                }
                if visibleNotes.isEmpty {
                    ContentUnavailableView(filter == .trash ? "휴지통이 비어 있습니다" : "노트를 만들어 시작하세요",
                        systemImage: filter == .trash ? "trash" : "doc.badge.plus")
                } else {
                    List(visibleNotes) { row in noteRow(row) }
                }
            }
          }
          .navigationTitle(filterTitle)
          .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                  Button { showsBackupImporter = true } label: { Image(systemName: "arrow.down.doc") }
                      .accessibilityLabel("백업에서 새 노트 복원").accessibilityIdentifier("restoreBackup")
              }
              ToolbarItem(placement: .topBarTrailing) {
                  Button { showsMaintenance = true } label: { Image(systemName: "externaldrive") }
                      .accessibilityLabel("저장 공간 정리").accessibilityIdentifier("storageMaintenance")
              }
              ToolbarItem(placement: .topBarTrailing) {
                  Button { requestName(.newFolder) } label: { Label("새 폴더", systemImage: "folder.badge.plus") }
                      .accessibilityIdentifier("newFolder")
              }
              ToolbarItem(placement: .topBarTrailing) {
                  Button { requestName(.newNote) } label: { Label("새 노트", systemImage: "plus") }
                      .accessibilityIdentifier("newNote").disabled(filter == .trash)
              }
              ToolbarItem(placement: .topBarTrailing) {
                  Button { Task { await session.load() } } label: { Image(systemName: "arrow.clockwise") }
                      .accessibilityLabel("목록 다시 불러오기").accessibilityIdentifier("reloadLibrary")
              }
          }
        }
        .disabled(session.isBusy)
        .fileImporter(isPresented: $showsBackupImporter, allowedContentTypes: [.minote]) { result in
            switch result {
            case .success(let url):
                let folder = selectedFolder
                session.beginBackupRestore(from: url, folderID: folder)
            case .failure(let error): session.operationError = error.localizedDescription
            }
        }
        .accessibilityIdentifier("libraryView")
    }

    private func noteRow(_ row: LibraryNoteRow) -> some View {
        HStack {
            Button { Task { await session.openNote(row.id) } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(row.title, systemImage: row.error == nil ? "doc.text" : "exclamationmark.triangle")
                        .font(.headline).foregroundStyle(.primary)
                    Text(row.error ?? "\(folderPath(row.metadata.folderID)) · \(Date(timeIntervalSince1970: row.metadata.modifiedAt).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(row.error == nil ? Color.secondary : .red)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
            .buttonStyle(.plain).accessibilityLabel(row.title).accessibilityIdentifier("note-\(row.id)")
            .disabled(row.metadata.trashedAt != nil)
            if row.metadata.trashedAt != nil {
                Button("복원") { Task { await session.restoreNote(row.id) } }
                    .buttonStyle(.bordered).accessibilityLabel("복원 \(row.title)")
                Button("영구 삭제", role: .destructive) { purging = row }
                    .buttonStyle(.bordered).accessibilityIdentifier("purgeNote-\(row.id)")
            } else {
                Menu {
                    Button("이름 변경") { requestName(.renameNote(row.id), initial: row.title) }.accessibilityIdentifier("renameNote")
                    Button("노트 이동") { moveRequest = MoveRequest(kind: .note, target: row.id) }.accessibilityIdentifier("moveNote")
                    Button("휴지통으로 이동", role: .destructive) { Task { await session.trashNote(row.id) } }.accessibilityIdentifier("trashNote")
                } label: { Image(systemName: "ellipsis.circle").padding(8) }
                .accessibilityLabel("노트 관리 \(row.title)")
            }
        }
    }
    private func filterButton(_ value: LibraryFilter, name: String, symbol: String, id: String) -> some View {
        Button { filter = value } label: { Label(name, systemImage: symbol).foregroundStyle(filter == value ? Color.accentColor : .primary) }
            .accessibilityIdentifier(id)
    }
    private var visibleNotes: [LibraryNoteRow] {
        session.notes.filter { row in
            if filter == .trash { return row.metadata.trashedAt != nil }
            guard row.metadata.trashedAt == nil else { return false }
            if case .folder(let id) = filter { return row.metadata.folderID == id }
            return true
        }
    }
    private var sortedFolders: [LibraryFolder] {
        session.folders.sorted { folderPath($0.id) == folderPath($1.id) ? $0.id.uuidString < $1.id.uuidString : folderPath($0.id) < folderPath($1.id) }
    }
    private var selectedFolder: UUID? { if case .folder(let id) = filter { return id }; return nil }
    private var filterTitle: String {
        switch filter { case .all: "모든 노트"; case .recent: "최근 노트"; case .trash: "휴지통"; case .folder(let id): folderPath(id) }
    }
    private func folderPath(_ id: UUID?) -> String {
        LibraryFolderLabels(folders: session.folders).label(for: id)
    }

    private func requestName(_ kind: NameRequest.Kind, initial: String = "") {
        name = initial; nameRequest = NameRequest(kind: kind)
    }
    private func nameSheet(_ request: NameRequest) -> some View {
        NavigationStack {
            Form { TextField("이름", text: $name).accessibilityIdentifier("nameField") }
                .navigationTitle(request.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { nameRequest = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            let entered = name, folder = selectedFolder
                            nameRequest = nil
                            Task {
                                switch request.kind {
                                case .newNote: await session.createNote(title: entered, folderID: folder)
                                case .newFolder: await session.createFolder(name: entered, parentID: folder)
                                case .renameNote(let id): await session.renameNote(id, title: entered)
                                case .renameFolder(let id): await session.renameFolder(id, name: entered)
                                }
                            }
                        }.accessibilityIdentifier("confirmName").disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.presentationDetents([.medium])
    }
    private func moveSheet(_ request: MoveRequest) -> some View {
        NavigationStack {
            List {
                moveDestination(nil, request: request)
                ForEach(sortedFolders) { folder in moveDestination(folder.id, request: request) }
            }.accessibilityIdentifier("moveDestinations").navigationTitle("이동할 폴더")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { moveRequest = nil } } }
        }.presentationDetents([.medium, .large])
    }
    private func moveDestination(_ id: UUID?, request: MoveRequest) -> some View {
        Button {
            moveRequest = nil
            Task {
                if request.kind == .note { await session.moveNote(request.target, folderID: id) }
                else { await session.moveFolder(request.target, parentID: id) }
            }
        } label: { Label(folderPath(id), systemImage: "folder") }
        .accessibilityLabel("대상 폴더 \(folderPath(id))")
        .disabled(request.kind == .folder && request.target == id)
    }
}

private enum LibraryFilter: Equatable { case all, recent, trash, folder(UUID) }
private struct NameRequest: Identifiable {
    enum Kind { case newNote, newFolder, renameNote(UUID), renameFolder(UUID) }
    let id = UUID()
    let kind: Kind
    var title: String { switch kind { case .newNote: "새 노트"; case .newFolder: "새 폴더"; case .renameNote: "노트 이름 변경"; case .renameFolder: "폴더 이름 변경" } }
}
private struct MoveRequest: Identifiable {
    enum Kind { case note, folder }
    let id = UUID()
    let kind: Kind
    let target: UUID
}
