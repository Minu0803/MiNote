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
    @Published private(set) var canvasGeneration = UUID()
    @Published var operationError: String?
    @Published private(set) var operationProgress: BackupProgress?
    private var progressOperationID: UUID?
    let exportRegistry: ExportFileRegistry
    private let backupService: NoteBackup
    private let libraryStore: LibraryStore?
    private var hasUnserializedDrawing = false
    private let importer = PDFImporter()
    private var pdfCache: [UUID: PDFDocument] = [:]
    private var pdfOrder: [UUID] = []
    private var thumbnails: [ThumbnailKey: UIImage] = [:]
    private var thumbnailOrder: [ThumbnailKey] = []
    var cachedPDFCount: Int { pdfCache.count }
    var cachedThumbnailCount: Int { thumbnails.count }
    private struct ThumbnailKey: Hashable { let id: UUID; let revision: Int64; let edge: Int }


    var currentPage: NotePage? {
        guard let document, document.pages.indices.contains(currentPageIndex) else { return nil }
        return document.pages[currentPageIndex]
    }
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

    init(store: DocumentStore, expectedID: UUID? = nil, saveDelay: Duration = .milliseconds(350),
         exportRegistry: ExportFileRegistry = .shared, backupService: NoteBackup = NoteBackup(), libraryStore: LibraryStore? = nil) {
        self.store = store
        self.expectedID = expectedID
        self.saveDelay = saveDelay
        self.exportRegistry = exportRegistry; self.backupService = backupService; self.libraryStore = libraryStore
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
            // Validate every retained source, including assets used only by deleted pages.
            for asset in loaded.pdfAssets { _ = try await pdf(for: asset.id, in: loaded) }
            let selectedPDF = try await pdf(for: loaded.pages[selected].pdfSource?.assetID, in: loaded)
            pdfDocument = selectedPDF
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
                // Also persist a v1/v2→v3 migration without changing document identity.
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
                else { saveState = .saving; if !isProcessing { scheduleSave() } }
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
            invalidateThumbnails()
            saveState = .saving
            if !isProcessing { scheduleSave() }
        } catch {
            hasUnserializedDrawing = true
            // Keep both the visible PencilKit drawing and the last saved portable document.
            saveState = .failed(error.localizedDescription)
            pendingSave?.cancel()
            pendingSave = nil
        }
    }

    func selectPage(_ index: Int) async {
        guard !isProcessing, let current = document, current.pages.indices.contains(index), index != currentPageIndex else { return }
        isProcessing = true; defer { finishProcessing() }
        operationError = nil
        guard let base = await flushedBase() else { return }
        do {
            var updated = base
            let page = updated.pages[index]
            _ = try InkAdapter.decode(page.strokes)
            let pdf = try await pdf(for: page.pdfSource?.assetID, in: base)
            guard stable(base), base.revision < Int64.max - 1 else { throw DocumentError.staleRevision }
            updated.lastOpenedPageID = page.id; updated.revision += 1
            try await store.save(updated)
            if await acceptCommitted(updated, over: base) { try publish(updated, pdf: pdf) }
        } catch { operationError = error.localizedDescription }
    }

    func applyPageCommand(_ command: PageCommand) async {
        guard !isProcessing, document != nil else { return }
        isProcessing = true; defer { finishProcessing() }
        operationError = nil
        guard let base = await flushedBase() else { return }
        do {
            let proposed = try PageCommands.apply(command, to: base)
            let selected = proposed.pages.first(where: { $0.id == proposed.lastOpenedPageID }) ?? proposed.pages[0]
            _ = try InkAdapter.decode(selected.strokes)
            let pdf = try await pdf(for: selected.pdfSource?.assetID, in: base)
            guard stable(base), base.revision < Int64.max - 1 else { throw DocumentError.staleRevision }
            let updated = try await store.applyPageCommand(command, expectedRevision: base.revision)
            if await acceptCommitted(updated, over: base) { try publish(updated, pdf: pdf) }
        } catch { operationError = error.localizedDescription }
    }

    func importPDF(from url: URL) async {
        guard !isProcessing, document != nil else { return }
        isProcessing = true; defer { finishProcessing() }
        operationError = nil
        guard let base = await flushedBase() else { return }
        do {
            let selectedID = base.pages[currentPageIndex].id
            let prepared = try await importer.prepare(url: url)
            // Parse before the durable transaction; no failing asset reopen follows commit.
            guard let pdf = PDFDocument(data: prepared.data) else { throw PDFError.invalidPDF }
            guard stable(base), base.revision < Int64.max - 1 else { throw DocumentError.staleRevision }
            let updated = try await store.attachPDF(data: prepared.data, asset: prepared.asset,
                pages: prepared.pages, afterPageID: selectedID, expectedRevision: base.revision)
            if await acceptCommitted(updated, over: base) {
                cache(pdf, for: prepared.asset.id)
                try publish(updated, pdf: pdf)
            }
        } catch { operationError = error.localizedDescription }
    }

    func exportPDF() async -> ExportedFile? {
        guard !isProcessing, document != nil else { return nil }
        isProcessing = true; defer { finishProcessing() }
        operationError = nil
        guard let snapshot = await flushedBase() else { return nil }
        var file: ExportedFile?
        do {
            var sources: [UUID: URL] = [:]
            for asset in snapshot.pdfAssets { sources[asset.id] = try await store.assetURL(for: asset) }
            guard stable(snapshot) else { throw DocumentError.staleRevision }
            let sourceURLs = sources
            let allocated = try await exportRegistry.allocate(filename: "MiNote.pdf"); file = allocated
            let destination = allocated.url
            try await Task.detached(priority: .userInitiated) {
                try PDFExporter.export(snapshot, sourceURLs: sourceURLs, destination: destination)
            }.value
            guard stable(snapshot) else { throw DocumentError.staleRevision }
            return allocated
        } catch {
            if let file { try? await exportRegistry.discard(file) }
            operationError = error.localizedDescription; return nil
        }
    }

    func exportBackup() async -> ExportedFile? {
        guard !isProcessing, document != nil else { return nil }
        isProcessing = true; let operation = UUID(); progressOperationID = operation
        defer { operationProgress = nil; progressOperationID = nil; finishProcessing() }
        operationError = nil
        guard let snapshot = await flushedBase() else { return nil }
        var file: ExportedFile?
        do {
            var sources: [UUID: URL] = [:]
            for asset in snapshot.pdfAssets { sources[asset.id] = try await store.assetURL(for: asset) }
            guard stable(snapshot) else { throw DocumentError.staleRevision }
            let allocated = try await exportRegistry.allocate(filename: "MiNote.minote"); file = allocated
            try await backupService.export(document: snapshot, assetURLs: sources, destination: allocated.url) { [weak self] progress in
                Task { @MainActor in if self?.progressOperationID == operation { self?.operationProgress = progress } }
            }
            try Task.checkCancellation()
            guard stable(snapshot) else { throw DocumentError.staleRevision }
            return allocated
        } catch {
            if let file { try? await exportRegistry.discard(file) }
            operationError = error is CancellationError ? "백업을 취소했습니다. 현재 필기는 유지됩니다." : error.localizedDescription
            return nil
        }
    }

    func purgeDeletedPage(_ id: UUID) async {
        guard !isProcessing, let libraryStore, document != nil else { return }
        isProcessing = true; defer { finishProcessing() }; operationError = nil
        guard let base = await flushedBase() else { return }
        do {
            guard stable(base), base.revision < Int64.max - 1 else { throw DocumentError.staleRevision }
            let updated = try await libraryStore.purgeDeletedPages([id], noteID: base.id, expectedRevision: base.revision)
            if await acceptCommitted(updated, over: base) { try publish(updated, pdf: pdfDocument) }
        } catch { operationError = error.localizedDescription }
    }

    private func flushedBase() async -> NoteDocument? {
        let before = document
        await flush()
        guard let base = document, base == before, stable(base) else {
            operationError = "현재 필기가 변경되었거나 저장하지 못했습니다. 저장을 완료한 뒤 다시 시도해 주세요."
            return nil
        }
        return base
    }

    private func stable(_ snapshot: NoteDocument) -> Bool {
        document == snapshot && saveState == .saved && !hasUnserializedDrawing
    }

    /// A queued native callback can arrive while the actor commits. Restore the
    /// pre-operation structure at a newer revision and retain its latest drawing.
    private func acceptCommitted(_ committed: NoteDocument, over base: NoteDocument) async -> Bool {
        guard !stable(base) else { return true }
        operationError = "처리 중 필기가 변경되어 페이지 작업을 취소했습니다. 현재 필기는 유지됩니다."
        guard var latest = document, max(latest.revision, committed.revision) < Int64.max else {
            saveState = .failed("필기를 유지했지만 리비전 한도 때문에 저장하지 못했습니다."); return false
        }
        latest.revision = max(latest.revision, committed.revision) + 1
        document = latest; savedRevision = nil
        let failedDrawing = hasUnserializedDrawing
        do {
            try await store.save(latest)
            if document == latest {
                savedRevision = latest.revision
                if !hasUnserializedDrawing { saveState = .saved }
            }
        } catch {
            if !failedDrawing { saveState = .failed(error.localizedDescription) }
        }
        return false
    }

    private func publish(_ updated: NoteDocument, pdf: PDFDocument?) throws {
        let selected = updated.pages.firstIndex(where: { $0.id == updated.lastOpenedPageID }) ?? 0
        let restored = try InkAdapter.decode(updated.pages[selected].strokes)
        document = updated; currentPageIndex = selected; drawing = restored; pdfDocument = pdf
        histories = Dictionary(uniqueKeysWithValues: updated.pages.map { ($0.id, $0.strokes) })
        savedRevision = updated.revision; hasUnserializedDrawing = false; saveState = .saved
        canvasGeneration = UUID(); invalidateThumbnails()
    }

    private func finishProcessing() {
        isProcessing = false
        if saveState == .saving { scheduleSave() }
    }

    private func pdf(for id: UUID?, in snapshot: NoteDocument) async throws -> PDFDocument? {
        guard let id else { return nil }
        guard let asset = snapshot.pdfAssets.first(where: { $0.id == id }) else { throw PDFError.missingAsset }
        if let cached = pdfCache[id] { cache(cached, for: id); return cached }
        let url = try await store.assetURL(for: asset)
        let loaded = try PDFValidation.open(url: url, asset: asset,
            referencedPages: (snapshot.pages + snapshot.deletedPages.map(\.page)).filter { $0.pdfSource?.assetID == id })
        cache(loaded, for: id); return loaded
    }

    private func cache(_ pdf: PDFDocument, for id: UUID) {
        pdfCache[id] = pdf; pdfOrder.removeAll { $0 == id }; pdfOrder.append(id)
        while pdfOrder.count > 2 { pdfCache.removeValue(forKey: pdfOrder.removeFirst()) }
    }

    func thumbnail(pageID: UUID, expectedRevision: Int64, maximumPixelEdge: Int = 256) async -> UIImage? {
        guard let snapshot = document, snapshot.revision == expectedRevision,
              let page = (snapshot.pages + snapshot.deletedPages.map(\.page)).first(where: { $0.id == pageID }) else { return nil }
        let key = ThumbnailKey(id: pageID, revision: expectedRevision, edge: maximumPixelEdge)
        if let image = thumbnails[key] { return image }
        do {
            let source = try await pdf(for: page.pdfSource?.assetID, in: snapshot)
            guard document == snapshot else { return nil }
            let image = try PageThumbnailRenderer.image(for: page,
                pdfPage: page.pdfSource.flatMap { source?.page(at: $0.index) }, maximumPixelEdge: maximumPixelEdge)
            guard document == snapshot else { return nil }
            thumbnails[key] = image; thumbnailOrder.append(key)
            while thumbnailOrder.count > 24 { thumbnails.removeValue(forKey: thumbnailOrder.removeFirst()) }
            return image
        } catch { return nil }
    }
    private func invalidateThumbnails() { thumbnails.removeAll(); thumbnailOrder.removeAll() }

    func retrySave() {
        guard document != nil, !isProcessing else { return }
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
            if document == snapshot, !hasUnserializedDrawing {
                savedRevision = snapshot.revision
                saveState = .saved
            }
        } catch {
            if document == snapshot, !hasUnserializedDrawing {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}
