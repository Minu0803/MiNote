import Combine
import MiNoteCore
import PencilKit

@MainActor
final class EditorSession: ObservableObject {
    enum SaveState: Equatable { case saving, saved, failed(String) }

    @Published private(set) var document: NoteDocument?
    @Published private(set) var drawing = PKDrawing()
    @Published private(set) var saveState: SaveState = .saving
    @Published private(set) var loadError: String?
    @Published private(set) var recoveryNotice: String?

    private let store: DocumentStore
    private let saveDelay: Duration
    private var history: [InkStroke] = []
    private var pendingSave: Task<Void, Never>?
    private var loading = false
    private var savedRevision: Int64?

    init(store: DocumentStore, saveDelay: Duration = .milliseconds(350)) {
        self.store = store
        self.saveDelay = saveDelay
    }

    var strokeCount: Int { drawing.strokes.count }
    var saveStatusLabel: String {
        switch saveState {
        case .saving: "저장 중"
        case .saved: "저장 완료"
        case .failed(let message): "저장 실패: \(message)"
        }
    }

    func loadIfNeeded() async {
        guard document == nil, !loading, loadError == nil else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await store.load()
            let loaded = result?.document ?? .blank()
            let restored = try InkAdapter.decode(loaded.pages[0].strokes)
            document = loaded
            drawing = restored
            history = loaded.pages[0].strokes
            savedRevision = result?.recoveredFromBackup == true ? nil : result.map { $0.document.revision }
            if result?.recoveredFromBackup == true {
                recoveryNotice = "복구본에서 노트를 복원했습니다. 원본 오류를 확인한 뒤 복구본을 보존합니다."
                saveState = .saving
                await persist(loaded)
            } else if result == nil {
                saveState = .saving
                await persist(loaded)
            } else {
                saveState = .saved
            }
        } catch {
            loadError = error.localizedDescription
            saveState = .failed(error.localizedDescription)
        }
    }

    func retryLoad() async {
        guard document == nil else { return }
        loadError = nil
        await loadIfNeeded()
    }

    /// Called for PencilKit changes and for explicit save/flush events.
    func receiveDrawing(_ updatedDrawing: PKDrawing) {
        drawing = updatedDrawing
        guard var current = document else { return }
        do {
            let strokes = try InkAdapter.encode(updatedDrawing, preserving: history)
            let prior = current.pages[0].strokes
            guard strokes != prior else {
                if savedRevision == current.revision { saveState = .saved }
                else { saveState = .saving; scheduleSave() }
                return
            }
            current.pages[0].strokes = strokes
            guard current.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
            current.revision += 1
            document = current
            for stroke in strokes where !history.contains(where: { $0.id == stroke.id }) {
                history.append(stroke)
            }
            saveState = .saving
            scheduleSave()
        } catch {
            // Keep both the visible PencilKit drawing and the last saved portable document.
            saveState = .failed(error.localizedDescription)
            pendingSave?.cancel()
            pendingSave = nil
        }
    }

    func retrySave() {
        guard document != nil else { return }
        receiveDrawing(drawing)
        guard case .saving = saveState, let snapshot = document else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in await self?.persist(snapshot) }
    }

    func flush(_ currentDrawing: PKDrawing? = nil) async {
        if let currentDrawing { receiveDrawing(currentDrawing) }
        pendingSave?.cancel()
        pendingSave = nil
        guard let snapshot = document, loadError == nil else { return }
        if case .failed = saveState { return }
        await persist(snapshot)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, saveDelay] in
            do { try await Task.sleep(for: saveDelay) } catch { return }
            guard let self, let snapshot = self.document else { return }
            await self.persist(snapshot)
        }
    }

    private func persist(_ snapshot: NoteDocument) async {
        saveState = .saving
        do {
            try await store.save(snapshot)
            if document?.id == snapshot.id, document?.revision == snapshot.revision {
                savedRevision = snapshot.revision
                saveState = .saved
            }
        } catch {
            if document?.id == snapshot.id, document?.revision == snapshot.revision {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}
