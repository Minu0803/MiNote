import Foundation
import MiNoteCore

/// Disambiguate sibling names at each path segment so ancestors remain recognizable.
struct LibraryFolderLabels {
    let folders: [LibraryFolder]
    func label(for id: UUID?) -> String {
        guard var next = id else { return "폴더 없음" }
        var parts: [String] = [], visited = Set<UUID>()
        while visited.insert(next).inserted, let folder = folders.first(where: { $0.id == next }) {
            let siblings = folders.filter { $0.parentID == folder.parentID && $0.name == folder.name }
            var name = folder.name
            if siblings.count > 1 {
                var length = 6
                while Set(siblings.map { String($0.id.uuidString.suffix(length)) }).count != siblings.count, length < 36 { length += 1 }
                name += " · \(folder.id.uuidString.suffix(length))"
            }
            parts.insert(name, at: 0)
            guard let parent = folder.parentID else { break }; next = parent
        }
        return parts.joined(separator: " / ")
    }
}
