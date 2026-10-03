import MiNoteCore
import SwiftUI

@main
struct MiNoteApp: App {
    @StateObject private var editor = EditorSession(store: DocumentStore(directory:
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MiNote")))
    var body: some Scene {
        WindowGroup { NoteEditorView(session: editor, onClose: {}) }
    }
}
