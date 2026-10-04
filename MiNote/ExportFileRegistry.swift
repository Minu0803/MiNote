import Foundation

struct ExportedFile: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let lease: UUID
    var isBackup: Bool { url.pathExtension == "minote" }
}

enum ExportRegistryError: LocalizedError {
    case invalid
    var errorDescription: String? { "공유 파일 기록을 확인할 수 없습니다. 파일 정리를 중단하고 기존 파일을 보존합니다." }
}

/// Persisted leases are conservative: interrupted consumers remain protected after restart.
actor ExportFileRegistry {
    static let shared = ExportFileRegistry(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MiNote-Exports"))
    private struct Record: Codable {
        let id: UUID
        let filename: String
        let createdAt: Double
        var leases: [UUID]
    }
    private struct Registry: Codable { var version = 1; var records: [Record] = [] }
    private let root: URL
    init(root: URL) { self.root = root }
    private var index: URL { root.appendingPathComponent("registry.json") }
    private func read() throws -> Registry {
        if FileManager.default.fileExists(atPath: root.path) {
            guard try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else { throw ExportRegistryError.invalid }
        }
        guard FileManager.default.fileExists(atPath: index.path) else { return Registry() }
        let attributes = try FileManager.default.attributesOfItem(atPath: index.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1024 * 1024,
              let registry = try? JSONDecoder().decode(Registry.self, from: Data(contentsOf: index)), registry.version == 1 else { throw ExportRegistryError.invalid }
        var ids = Set<UUID>(), leases = Set<UUID>()
        for record in registry.records {
            guard ids.insert(record.id).inserted, ["MiNote.pdf", "MiNote.minote"].contains(record.filename), record.createdAt.isFinite, record.createdAt >= 0,
                  record.leases.allSatisfy({ leases.insert($0).inserted }) else { throw ExportRegistryError.invalid }
        }
        return registry
    }
    private func write(_ registry: Registry) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(registry)
        guard data.count <= 1024 * 1024 else { throw ExportRegistryError.invalid }
        try data.write(to: index, options: .atomic)
    }
    func allocate(filename: String, now: Date = Date()) throws -> ExportedFile {
        guard ["MiNote.pdf", "MiNote.minote"].contains(filename), now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 >= 0 else { throw ExportRegistryError.invalid }
        var registry = try read()
        let record = Record(id: UUID(), filename: filename, createdAt: now.timeIntervalSince1970, leases: [UUID()])
        let folder = root.appendingPathComponent(record.id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { registry.records.append(record); try write(registry) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return ExportedFile(id: record.id, url: folder.appendingPathComponent(filename), lease: record.leases[0])
    }
    func acquire(_ file: ExportedFile) throws -> UUID {
        var registry = try read()
        guard let i = registry.records.firstIndex(where: { $0.id == file.id }),
              file.url.standardizedFileURL == root.appendingPathComponent(file.id.uuidString).appendingPathComponent(registry.records[i].filename).standardizedFileURL,
              try FileManager.default.attributesOfItem(atPath: file.url.path)[.type] as? FileAttributeType == .typeRegular else { throw ExportRegistryError.invalid }
        let lease = UUID(); registry.records[i].leases.append(lease); try write(registry); return lease
    }
    func release(_ lease: UUID) throws {
        var registry = try read()
        guard let i = registry.records.firstIndex(where: { $0.leases.contains(lease) }) else { return }
        registry.records[i].leases.removeAll { $0 == lease }; try write(registry)
    }
    func discard(_ file: ExportedFile) throws {
        try release(file.lease)
        var registry = try read()
        guard let i = registry.records.firstIndex(where: { $0.id == file.id }), registry.records[i].leases.isEmpty else { return }
        let folder = root.appendingPathComponent(file.id.uuidString)
        if FileManager.default.fileExists(atPath: folder.path), try safeToRemove(folder, filename: registry.records[i].filename) { try FileManager.default.removeItem(at: folder) }
        else if FileManager.default.fileExists(atPath: folder.path) { return }
        registry.records.remove(at: i); try write(registry)
    }
    func cleanExpired(now: Date = Date()) throws -> [URL] {
        var registry = try read(), removed: [URL] = []
        for record in registry.records where record.leases.isEmpty && now.timeIntervalSince1970 - record.createdAt > 7 * 86400 {
            let folder = root.appendingPathComponent(record.id.uuidString)
            if FileManager.default.fileExists(atPath: folder.path) {
                guard try safeToRemove(folder, filename: record.filename) else { continue }
                try FileManager.default.removeItem(at: folder); removed.append(folder)
            }
            registry.records.removeAll { $0.id == record.id }
        }
        try write(registry); return removed
    }
    private func safeToRemove(_ folder: URL, filename: String) throws -> Bool {
        guard try FileManager.default.attributesOfItem(atPath: folder.path)[.type] as? FileAttributeType == .typeDirectory else { return false }
        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for item in contents {
            guard item.lastPathComponent == filename,
                  try FileManager.default.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType == .typeRegular else { return false }
        }
        return true
    }
}
