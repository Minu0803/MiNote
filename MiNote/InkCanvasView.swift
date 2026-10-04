import PencilKit

/// The production canvas owns one real UndoManager for native ink and commands.
/// PencilKit's opaque registrations cannot replay across drawing replacements;
/// delegate snapshots are registered explicitly by InkUndoCoordinator instead.
final class InkCanvasView: PKCanvasView {
    private let history = InkHistoryManager()
    override var undoManager: UndoManager? { history }
    var canReplayInkHistory: () -> Bool {
        get { history.canReplay }
        set { history.canReplay=newValue }
    }
    override init(frame: CGRect) {
        super.init(frame:frame)
        history.groupsByEvent=false
        history.disableUndoRegistration()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class InkHistoryManager: UndoManager {
    var canReplay: () -> Bool = { false }
    // NSUndoManager must enter replay with registration enabled so it opens the
    // inverse group. Native PencilKit registrations remain disabled outside replay.
    override func undo() {
        guard canReplay() else { return }
        let disabled = !isUndoRegistrationEnabled
        if disabled { enableUndoRegistration() }
        super.undo()
        if disabled { disableUndoRegistration() }
    }
    override func redo() {
        guard canReplay() else { return }
        let disabled = !isUndoRegistrationEnabled
        if disabled { enableUndoRegistration() }
        super.redo()
        if disabled { disableUndoRegistration() }
    }
}
