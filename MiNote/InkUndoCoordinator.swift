import MiNoteCore
import PencilKit

/// Native gestures and portable moves share the production canvas UndoManager.
@MainActor final class InkUndoCoordinator {
    private final class Entry {
        let page: UUID, generation: UUID
        let before: [InkStroke]?, beforeDrawing: PKDrawing
        var after: [InkStroke]?, afterDrawing: PKDrawing
        init(page: UUID, generation: UUID, before: [InkStroke]?, after: [InkStroke]?, beforeDrawing: PKDrawing, afterDrawing: PKDrawing) {
            self.page=page; self.generation=generation; self.before=before; self.after=after
            self.beforeDrawing=beforeDrawing; self.afterDrawing=afterDrawing
        }
    }
    private weak var canvas: PKCanvasView?
    private weak var session: EditorSession?
    private let applyDrawing: (PKDrawing) -> Void
    private let onChange: () -> Void
    private var nativeEntry: Entry?
    init(canvas: PKCanvasView, session: EditorSession, applyDrawing: @escaping (PKDrawing) -> Void, onChange: @escaping () -> Void) {
        self.canvas=canvas; self.session=session; self.applyDrawing=applyDrawing; self.onChange=onChange
    }
    func beginNativeGesture() { nativeEntry=nil }
    func recordNativeChange(before: [InkStroke]?, drawing: PKDrawing) {
        guard let session, let page=session.currentPage, let manager=canvas?.undoManager, session.drawing != drawing else { return }
        if let entry=nativeEntry {
            entry.after=session.serializedVisibleInk; entry.afterDrawing=session.drawing
        } else {
            let entry=Entry(page:page.id,generation:session.canvasGeneration,before:before,after:session.serializedVisibleInk,
                            beforeDrawing:drawing,afterDrawing:session.drawing)
            nativeEntry=entry; register(entry,reverse:false,manager:manager,action:"필기")
        }
        onChange()
    }
    func move(dx: Double, dy: Double) throws {
        guard let session, let manager=canvas?.undoManager else { throw DocumentError.invalidDocument("실행 취소를 사용할 수 없습니다.") }
        nativeEntry=nil
        guard let t=try session.translateSelectedInk(dx:dx,dy:dy) else { return }
        applyWithoutRegistration(session.drawing,manager:manager)
        register(Entry(page:t.pageID,generation:t.generation,before:t.before,after:t.after,beforeDrawing:t.beforeDrawing,afterDrawing:t.afterDrawing),reverse:false,manager:manager,action:"획 이동")
        onChange()
    }
    private func register(_ entry: Entry, reverse: Bool, manager: UndoManager, action: String) {
        let wasEnabled=manager.isUndoRegistrationEnabled
        if !wasEnabled { manager.enableUndoRegistration() }
        let grouping = !manager.isUndoing && !manager.isRedoing
        if grouping { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget:self) { target in target.replay(entry,reverse:reverse,action:action) }
        manager.setActionName(action)
        if grouping { manager.endUndoGrouping() }
        if !wasEnabled { manager.disableUndoRegistration() }
    }
    private func replay(_ entry: Entry, reverse: Bool, action: String) {
        guard let session, let manager=canvas?.undoManager else { return }
        nativeEntry=nil
        let from = reverse ? entry.before : entry.after, to = reverse ? entry.after : entry.before
        let expectedDrawing = reverse ? entry.beforeDrawing : entry.afterDrawing
        let targetDrawing = reverse ? entry.afterDrawing : entry.beforeDrawing
        do {
            guard session.drawing == expectedDrawing else { throw DocumentError.staleRevision }
            if let from, let to {
                try session.restoreInk(to,replacing:from,pageID:entry.page,generation:entry.generation,native:targetDrawing)
            } else {
                try session.restoreUnserializedInk(targetDrawing,replacing:expectedDrawing,portable:to,pageID:entry.page,generation:entry.generation)
            }
            applyWithoutRegistration(session.drawing,manager:manager)
            register(entry,reverse:!reverse,manager:manager,action:action)
        } catch { session.operationError=error.localizedDescription }
        onChange()
    }
    private func applyWithoutRegistration(_ drawing: PKDrawing, manager: UndoManager) {
        let wasEnabled=manager.isUndoRegistrationEnabled
        if wasEnabled { manager.disableUndoRegistration() }
        applyDrawing(drawing)
        if wasEnabled { manager.enableUndoRegistration() }
    }
}
