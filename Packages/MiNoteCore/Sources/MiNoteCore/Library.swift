import Foundation

public struct LibraryCatalog: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var revision: Int64
    public var notes: [LibraryNote]
    public var folders: [LibraryFolder]
    public init(revision: Int64 = 0, notes: [LibraryNote] = [], folders: [LibraryFolder] = []) {
        self.revision = revision; self.notes = notes; self.folders = folders
    }
}

public struct LibraryNote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var folderID: UUID?
    public var modifiedAt: Double
    public var trashedAt: Double?
    public init(id: UUID, folderID: UUID? = nil, modifiedAt: Double, trashedAt: Double? = nil) {
        self.id = id; self.folderID = folderID; self.modifiedAt = modifiedAt; self.trashedAt = trashedAt
    }
}

public struct LibraryFolder: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
        self.id = id; self.name = name; self.parentID = parentID
    }
}

public struct LibraryLoadResult: Sendable {
    public let catalog: LibraryCatalog
    public let recoveredNoteIDs: [UUID]
    public let recoveryNotice: String?
}

public enum LibraryError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(Int), corruptCatalog, invalidCatalog(String)
    case notLoaded, busy, conflict, noteMissing(UUID), documentMissing(UUID), folderMissing, noteTrashed
    case invalidPurgeJournal
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "지원하지 않는 라이브러리 버전입니다 (\(version)). 원본을 보존합니다."
        case .corruptCatalog: "라이브러리와 복구본을 읽을 수 없습니다. 기록은 보존됩니다."
        case .invalidCatalog(let reason): "라이브러리에 잘못된 정보가 있습니다: \(reason)"
        case .notLoaded: "라이브러리를 먼저 불러와 주세요."
        case .busy: "진행 중인 문서 작업이 있습니다. 잠시 뒤 다시 시도해 주세요."
        case .conflict: "디스크의 라이브러리가 변경되었습니다. 다시 불러와 주세요."
        case .noteMissing: "노트를 찾을 수 없습니다. 목록을 다시 불러와 주세요."
        case .documentMissing: "노트 파일과 복구본이 없습니다. 빈 노트로 교체하지 않습니다."
        case .folderMissing: "대상 폴더를 찾을 수 없습니다."
        case .noteTrashed: "휴지통에서 복원한 뒤 노트를 열 수 있습니다."
        case .invalidPurgeJournal: "영구 삭제 복구 기록을 확인할 수 없습니다. 편집을 중단하고 원본을 보존합니다."
        }
    }
}
