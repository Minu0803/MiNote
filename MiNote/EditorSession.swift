import Combine
import MiNoteCore
import PencilKit
import PDFKit

@MainActor
final class EditorSession: ObservableObject {
    enum SaveState: Equatable { case saving, saved, failed(String) }

    @Published private(set) var document: NoteDocument?
    @Published private(set) var drawing = PKDrawing()
    @Published private(set) var saveState: SaveState = .saving
    @Published private(set) var loadError: String?
    @Published private(set) var recoveryNotice: String?

    @Published private(set) var currentPageIndex = 0
    @Published private(set) var pdfDocument: PDFDocument?
    @Published private(set) var isProcessing = false
    @Published var operationError: String?
    private var hasUnserializedDrawing = false
    private let importer = PDFImporter()

    var currentPage: NotePage? { document?.pages[currentPageIndex] }
    var currentPDFPage: PDFPage? {
        guard let index = currentPage?.pdfSource?.index else { return nil }
        return pdfDocument?.page(at: index)
    }

    private let store: DocumentStore
    private let expectedID: UUID?
    private let saveDelay: Duration
    private var histories: [UUID: [InkStroke]] = [:]
    private var pendingSave: Task<Void, Never>?
    private var loading = false
    private var savedRevision: Int64?

    init(store: DocumentStore, expectedID: UUID? = nil, saveDelay: Duration = .milliseconds(350)) {
        self.store = store
        self.expectedID = expectedID
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
            if let expectedID {
                guard result?.document.id == expectedID else { throw LibraryError.documentMissing(expectedID) }
            }
            let loaded = result?.document ?? .blank()
            let selected = loaded.pages.firstIndex(where: { $0.id == loaded.lastOpenedPageID }) ?? 0
            let restored = try InkAdapter.decode(loaded.pages[selected].strokes)
            if let asset = loaded.pdfAsset {
                let url = try await store.assetURL(for: asset)
                pdfDocument = try PDFValidation.open(url: url, for: loaded)
            }
            currentPageIndex = selected
            document = loaded
            drawing = restored
            histories = Dictionary(uniqueKeysWithValues: loaded.pages.map { ($0.id, $0.strokes) })
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
                // Also persist a v1→v2 migration without changing document identity.
                await persist(loaded)
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
        guard !isProcessing else { return }
        drawing = updatedDrawing
        guard var current = document else { return }
        do {
            let pageID = current.pages[currentPageIndex].id
            var history = histories[pageID] ?? []
            let strokes = try InkAdapter.encode(updatedDrawing, preserving: history)
            let prior = current.pages[currentPageIndex].strokes
            hasUnserializedDrawing = false
            guard strokes != prior else {
                if savedRevision == current.revision { saveState = .saved }
                else { saveState = .saving; scheduleSave() }
                return
            }
            current.pages[currentPageIndex].strokes = strokes
            guard current.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
            current.revision += 1
            document = current
            for stroke in strokes where !history.contains(where: { $0.id == stroke.id }) {
                history.append(stroke)
            }
            histories[pageID] = history
            saveState = .saving
            scheduleSave()
        } catch {
            hasUnserializedDrawing = true
            // Keep both the visible PencilKit drawing and the last saved portable document.
            saveState = .failed(error.localizedDescription)
            pendingSave?.cancel()
            pendingSave = nil
        }
    }

    func selectPage(_ index: Int) {
        guard !isProcessing, !hasUnserializedDrawing, var current = document,
              current.pages.indices.contains(index), index != currentPageIndex else { return }
        do {
            let restored = try InkAdapter.decode(current.pages[index].strokes)
            guard current.revision < Int64.max else { throw DocumentError.invalidDocument("리비전 한도") }
            current.lastOpenedPageID = current.pages[index].id
            current.revision += 1
            currentPageIndex = index
            drawing = restored
            document = current
            saveState = .saving
            scheduleSave()
        } catch { operationError = error.localizedDescription }
    }

    func importPDF(from url: URL) async {
        guard !isProcessing, let current = document else { return }
        guard current.pdfAsset == nil else {
            operationError = "현재 노트에는 PDF가 연결되어 있습니다. 다른 PDF는 새 노트로 가져와 주세요."
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        operationError = nil
        await flush()
        guard saveState == .saved, let base = document else {
            operationError = "현재 필기를 먼저 저장해 주세요. 저장을 재시도한 뒤 PDF를 가져올 수 있습니다."
            return
        }
        var committed = false
        do {
            let prepared = try await importer.prepare(url: url)
            let imported = try await store.attachPDF(data: prepared.data, asset: prepared.asset,
                pages: prepared.pages, afterPageID: base.pages[currentPageIndex].id, expectedRevision: base.revision)
            committed = true
            let assetURL = try await store.assetURL(for: prepared.asset)
            let pdf = try PDFValidation.open(url: assetURL, for: imported)
            document = imported
            pdfDocument = pdf
            histories = Dictionary(uniqueKeysWithValues: imported.pages.map { ($0.id, $0.strokes) })
            savedRevision = imported.revision
            currentPageIndex = base.pages.count
            drawing = PKDrawing()
            saveState = .saved
        } catch {
            if committed {
                // A disk transaction succeeded but its assets could not be reopened.
                // Block edits against a stale in-memory document; retry authoritative load.
                document = nil
                pdfDocument = nil
                loadError = error.localizedDescription
                saveState = .failed(error.localizedDescription)
            }
            operationError = error.localizedDescription
        }
    }

    func exportPDF() async -> URL? {
        guard !isProcessing, document?.pdfAsset != nil else { return nil }
        isProcessing = true
        defer { isProcessing = false }
        operationError = nil
        await flush()
        guard saveState == .saved, let snapshot = document, !snapshot.pdfAssets.isEmpty else {
            operationError = "최신 필기를 먼저 저장해 주세요. 저장을 재시도한 뒤 내보낼 수 있습니다."
            return nil
        }
        do {
            var sources: [UUID: URL] = [:]
            for sourceAsset in snapshot.pdfAssets { sources[sourceAsset.id] = try await store.assetURL(for: sourceAsset) }
            let sourceURLs = sources
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiNote-Exports").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("MiNote.pdf")
            try await Task.detached(priority: .userInitiated) {
                try PDFExporter.export(snapshot, sourceURLs: sourceURLs, destination: destination)
            }.value
            return destination
        } catch {
            operationError = error.localizedDescription
            return nil
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
