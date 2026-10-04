import XCTest
@testable import MiNote

@MainActor final class ExportFileRegistryTests: XCTestCase {
    func testExportLeaseSurvivesPreviewShareRestartAndCleanup() async throws {
        let root = try directory(), registry = ExportFileRegistry(root: root), now = Date()
        let file = try await registry.allocate(filename: "MiNote.minote", now: now)
        try Data("archive".utf8).write(to: file.url)
        let share = try await registry.acquire(file)
        let future = now.addingTimeInterval(8 * 86400)
        let initial = try await registry.cleanExpired(now: future); XCTAssertTrue(initial.isEmpty)
        try await registry.release(file.lease)
        let reopened = ExportFileRegistry(root: root), stillHeld = try await reopened.cleanExpired(now: future)
        XCTAssertTrue(stillHeld.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        try await reopened.release(share)
        let removed = try await reopened.cleanExpired(now: future)
        XCTAssertEqual(removed, [file.url.deletingLastPathComponent()]); XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }
    func testUnknownFilesAndCorruptRegistryAreNeverDeleted() async throws {
        let root = try directory(), unknown = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        let raw = unknown.appendingPathComponent("keep.pdf"); try Data("keep".utf8).write(to: raw)
        let registry = ExportFileRegistry(root: root)
        let file = try await registry.allocate(filename: "MiNote.pdf", now: Date(timeIntervalSince1970: 0))
        try Data("PDF".utf8).write(to: file.url); try await registry.release(file.lease)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("registry.json"))
        do { _ = try await ExportFileRegistry(root: root).cleanExpired(now: Date()); XCTFail("corrupt registry") } catch { }
        XCTAssertEqual(try Data(contentsOf: raw), Data("keep".utf8)); XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
    }
    func testUnexpectedContentsInRegisteredDirectoryAreProtected() async throws {
        let root = try directory(), registry = ExportFileRegistry(root: root)
        let file = try await registry.allocate(filename: "MiNote.pdf", now: Date(timeIntervalSince1970: 0))
        try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: false)
        let keep = file.url.appendingPathComponent("keep.json"); try Data("keep".utf8).write(to: keep)
        try await registry.release(file.lease)
        let result = try await registry.cleanExpired(now: Date())
        XCTAssertTrue(result.isEmpty); XCTAssertEqual(try Data(contentsOf: keep), Data("keep".utf8))
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
}
