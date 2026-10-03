import Foundation
import XCTest
@testable import MiNoteCore

@MainActor enum LibraryTestSupport {
    static func directory(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    static func data(_ name: String, extension ext: String = "json") throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "PortableInk"))
        return try Data(contentsOf: url)
    }
    static func seedLegacy(at root: URL) throws -> NoteDocument {
        let raw = try data("source"), document = try DocumentCodec.decode(raw)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try data("source", extension: "pdf").write(to: root.appendingPathComponent(try XCTUnwrap(document.pdfAssets.first).relativePath))
        try raw.write(to: root.appendingPathComponent("document.json"))
        try raw.write(to: root.appendingPathComponent("document.backup.json"))
        return document
    }
}
