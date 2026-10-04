import Combine
import Foundation
import MiNoteCore

struct LibraryNoteRow: Identifiable {
    let metadata: LibraryNote
    let title: String
    let error: String?
    var id: UUID { metadata.id }
}

@MainActor final class LibrarySession: ObservableObject {
    @Published private(set) var notes: [LibraryNoteRow] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published private(set) var selectedEditor: EditorSession?
    @Published private(set) var isBusy = false {
        didSet { if !isBusy { startNextBackupRestore() } }
    }
    @Published private(set) var loadError: String?
    @Published private(set) var recoveryNotice: String?
    @Published var operationError: String?
    @Published private(set) var operationProgress: BackupProgress?
    @Published private(set) var maintenanceReport: MaintenanceReport?
    @Published private(set) var cleanedExports = 0
    let exportRegistry: ExportFileRegistry
    private var progressOperationID: UUID?
    private var catalogRevision: Int64 = 0
    private let store: LibraryStore
    private var openedRevision: Int64?
    private var loaded = false

    init(store: LibraryStore, exportRegistry: ExportFileRegistry = .shared) { self.store = store; self.exportRegistry = exportRegistry }

    func load() async {
        guard !isBusy, selectedEditor == nil else { return }
        isBusy = true; defer { isBusy = false }
        do { try await refresh(); loadError = nil; loaded = true }
        catch { loadError = error.localizedDescription; loaded = false }
    }

    func openNote(_ id: UUID) async {
        guard !isBusy, loaded else { return }
        if selectedEditor?.document?.id == id { return }
        isBusy = true; defer { isBusy = false }
        operationError = nil
        do {
            guard await closeActive() else { return }
            guard let row = notes.first(where: { $0.id == id }) else { throw LibraryError.noteMissing(id) }
            guard row.metadata.trashedAt == nil else { throw LibraryError.noteTrashed }
            let editor = EditorSession(store: try await store.documentStore(for: id), expectedID: id, exportRegistry: exportRegistry, libraryStore: store)
            await editor.loadIfNeeded()
            guard let document = editor.document else { throw LibrarySessionError.message(editor.loadError ?? "노트를 열 수 없습니다.") }
            selectedEditor = editor; openedRevision = document.revision
        } catch { operationError = error.localizedDescription }
    }

    @discardableResult func closeNote() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; defer { isBusy = false }
        operationError = nil
        return await closeActive()
    }

    private func closeActive() async -> Bool {
        guard let editor = selectedEditor else { return true }
        guard !editor.isProcessing else { operationError = "문서 처리를 마친 뒤 닫을 수 있습니다."; return false }
        await editor.flush()
        guard editor.saveState == .saved, let document = editor.document else {
            operationError = "현재 필기를 저장하지 못했습니다. 재시도한 뒤 노트를 닫아 주세요."
            return false
        }
        do {
            if document.revision != openedRevision {
                try await store.markModified(id: document.id, at: Date().timeIntervalSince1970)
            }
            // Publish removal only after both document and metadata are durable.
            try await refresh()
            // A native callback may arrive during either awaited operation.
            // Keep the editor if its latest drawing was not included in this save.
            guard editor.saveState == .saved, editor.document == document else {
                operationError = "닫는 동안 필기가 변경되었습니다. 저장이 완료된 뒤 다시 닫아 주세요."
                return false
            }
            selectedEditor = nil; openedRevision = nil
            return true
        } catch { operationError = error.localizedDescription; return false }
    }

    private func refresh() async throws {
        let result = try await store.load()
        var rows: [LibraryNoteRow] = []
        for note in result.catalog.notes {
            do {
                let documentStore = try await store.documentStore(for: note.id)
                guard let loaded = try await documentStore.load() else { throw LibraryError.documentMissing(note.id) }
                guard loaded.document.id == note.id else { throw LibraryError.conflict }
                rows.append(LibraryNoteRow(metadata: note, title: loaded.document.title, error: nil))
            } catch { rows.append(LibraryNoteRow(metadata: note, title: "열 수 없는 노트 (\(note.id.uuidString.prefix(8)))", error: error.localizedDescription)) }
        }
        notes = rows.sorted {
            $0.metadata.modifiedAt == $1.metadata.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.metadata.modifiedAt > $1.metadata.modifiedAt
        }
        folders = result.catalog.folders
        catalogRevision = result.catalog.revision
        if let notice = result.recoveryNotice { recoveryNotice = notice }
    }

    private func mutate(_ action: () async throws -> Void) async {
        guard !isBusy, loaded else { return }
        isBusy = true; defer { isBusy = false }
        operationError = nil
        guard await closeActive() else { return }
        do { try await action(); try await refresh() }
        catch {
            operationError = error.localizedDescription
            // A durable note may exist despite catalog failure; recover it on reload.
            do { try await refresh() } catch { loadError = error.localizedDescription; loaded = false }
        }
    }
    func createNote(title: String, folderID: UUID?) async {
        await mutate { _ = try await store.createNote(title: title, folderID: folderID) }
    }
    func renameNote(_ id: UUID, title: String) async {
        await mutate { try await store.renameNote(id: id, title: title) }
    }
    func moveNote(_ id: UUID, folderID: UUID?) async {
        await mutate { try await store.moveNote(id: id, folderID: folderID) }
    }
    func trashNote(_ id: UUID) async { await mutate { try await store.trashNote(id: id) } }
    func restoreNote(_ id: UUID) async { await mutate { try await store.restoreNote(id: id) } }
    func createFolder(name: String, parentID: UUID?) async {
        await mutate { _ = try await store.createFolder(name: name, parentID: parentID) }
    }
    func renameFolder(_ id: UUID, name: String) async {
        await mutate { try await store.renameFolder(id: id, name: name) }
    }
    func moveFolder(_ id: UUID, parentID: UUID?) async {
        await mutate { try await store.moveFolder(id: id, parentID: parentID) }
    }
    private struct BackupRequest { let url: URL; let folderID: UUID?; let scoped: Bool }
    private var pendingBackups: [BackupRequest] = []
    private(set) var backupRestoreTask: Task<Void, Never>?
    @Published private(set) var isRestoringBackup = false

    /// Both Files entry points retain requests while startup or another operation owns the library.
    func beginBackupRestore(from url: URL, folderID: UUID?) {
        pendingBackups.append(BackupRequest(url: url, folderID: folderID, scoped: url.startAccessingSecurityScopedResource()))
        isRestoringBackup = true
        startNextBackupRestore()
    }
    func cancelBackupRestore() {
        for request in pendingBackups where request.scoped { request.url.stopAccessingSecurityScopedResource() }
        pendingBackups.removeAll()
        backupRestoreTask?.cancel()
        if backupRestoreTask == nil { isRestoringBackup = false }
    }
    private func startNextBackupRestore() {
        guard backupRestoreTask == nil else { return }
        guard !pendingBackups.isEmpty else { isRestoringBackup = false; return }
        guard !isBusy else { return }
        let request = pendingBackups.removeFirst()
        backupRestoreTask = Task {
            var requeued = false
            defer {
                if request.scoped && !requeued { request.url.stopAccessingSecurityScopedResource() }
                backupRestoreTask = nil
                startNextBackupRestore()
            }
            do {
                try Task.checkCancellation()
                // An operation may start between task creation and its first turn.
                if isBusy { pendingBackups.insert(request, at: 0); requeued = true; return }
                if !loaded { await load() }
                try Task.checkCancellation()
                guard loaded else { throw LibrarySessionError.message(loadError ?? "라이브러리를 불러온 뒤 다시 복원해 주세요.") }
                await restoreBackup(from: request.url, folderID: request.folderID)
            } catch { operationError = error.localizedDescription }
        }
    }
    func restoreBackup(from url: URL, folderID: UUID?) async {
        guard !isBusy, loaded else { return }
        let operation = UUID(); progressOperationID = operation
        defer { progressOperationID = nil; operationProgress = nil }
        await mutate {
            let access = BackupFileAccess()
            let backup = try await access.prepare(url: url) { [weak self] progress in
                Task { @MainActor in if self?.progressOperationID == operation { self?.operationProgress = progress } }
            }
            do { _ = try await store.restoreBackup(backup, folderID: folderID) }
            catch { await access.removeStaging(backup); throw error }
            await access.removeStaging(backup)
        }
    }
    func inspectMaintenance() async {
        maintenanceReport = nil; cleanedExports = 0
        await mutate { maintenanceReport = try await store.maintenanceReport() }
    }
    func cleanStorage() async {
        await mutate {
            maintenanceReport = try await store.cleanUnreferencedFiles()
            cleanedExports = try await exportRegistry.cleanExpired().count
        }
    }
    func purgeNote(_ id: UUID) async {
        guard selectedEditor == nil else { operationError = "라이브러리로 돌아간 뒤 휴지통 노트를 영구 삭제해 주세요."; return }
        await mutate { try await store.purgeTrashedNote(id, expectedCatalogRevision: catalogRevision) }
    }
}

private enum LibrarySessionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
