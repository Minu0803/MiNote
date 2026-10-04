import MiNoteCore
import SwiftUI

@main
struct MiNoteApp: App {
    @StateObject private var library = LibrarySession(store: LibraryStore(directory:
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("MiNote")))
    var body: some Scene {
        WindowGroup {
            LibraryView(session: library)
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "minote" {
                        library.beginBackupRestore(from: url, folderID: nil)
                    }
                }
        }
    }
}
