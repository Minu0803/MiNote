import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class NoteBackupTests: XCTestCase {
    func fixture(at root: URL) throws -> (NoteDocument, [UUID: URL]) {
        let document = try DocumentCodec.decode(LibraryTestSupport.data("multi-source"))
        var urls: [UUID: URL] = [:]
        for asset in document.pdfAssets {
            let url = root.appendingPathComponent(asset.id.uuidString + ".pdf")
            try LibraryTestSupport.data("source", extension: "pdf").write(to: url)
            urls[asset.id] = url
        }
        return (document, urls)
    }

    func testArchiveKeepsV3InkPagesAndEveryPDFByte() async throws {
        let root = try LibraryTestSupport.directory(self), archive = root.appendingPathComponent("note.minote")
        let (document, urls) = try fixture(at: root)
        let service = NoteBackup()
        try await service.export(document: document, assetURLs: urls, destination: archive)
        let restored = try await service.validate(source: archive, stagingRoot: root.appendingPathComponent("staging"))
        XCTAssertEqual(restored.document, document)
        for asset in document.pdfAssets {
            XCTAssertEqual(try Data(contentsOf: restored.stagingDirectory.appendingPathComponent(asset.relativePath)),
                           try Data(contentsOf: XCTUnwrap(urls[asset.id])))
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import sys,zipfile,json; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; m=json.loads(z.read('manifest.json')); assert m['archiveVersion']==1; assert len(z.infolist())==4; assert all(i.compress_type==0 for i in z.infolist()); assert all(z.getinfo(e['name']).CRC==e['crc32'] and z.getinfo(e['name']).file_size==e['byteCount'] for e in m['entries'])", archive.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }

    func testFailedExportPreservesDestinationAndRemovesOnlyOwnedTemporaryFiles() async throws {
        let root = try LibraryTestSupport.directory(self), archive = root.appendingPathComponent("note.minote")
        let (document, urls) = try fixture(at: root)
        try await NoteBackup().export(document: document, assetURLs: urls, destination: archive)
        let previous = try Data(contentsOf: archive), before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let failing = NoteBackup(chunkWriter: { _, _ in throw POSIXError(.ENOSPC) })
        do { try await failing.export(document: document, assetURLs: urls, destination: archive); XCTFail("expected disk error") }
        catch { XCTAssertEqual((error as? POSIXError)?.code, .ENOSPC) }
        XCTAssertEqual(try Data(contentsOf: archive), previous)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), before)
        // Successful replacement must also work, rather than only writing a new path.
        try await NoteBackup().export(document: document, assetURLs: urls, destination: archive)
        XCTAssertEqual(try Data(contentsOf: archive), previous)
    }

    func testCancelledExportPreservesDestination() async throws {
        let root = try LibraryTestSupport.directory(self), archive = root.appendingPathComponent("note.minote")
        let (document, urls) = try fixture(at: root)
        try Data("previous archive".utf8).write(to: archive)
        let cancelling = NoteBackup(chunkWriter: { handle, data in
            try handle.write(contentsOf: data)
            withUnsafeCurrentTask { $0?.cancel() }
        })
        do { try await cancelling.export(document: document, assetURLs: urls, destination: archive); XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: archive), Data("previous archive".utf8))
        let task = Task { try await NoteBackup().export(document: document, assetURLs: urls, destination: archive) }
        task.cancel()
        do { try await task.value; XCTFail("expected task cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCRCFailureAndFutureSchemaNeverPublishStaging() async throws {
        let root = try LibraryTestSupport.directory(self), archive = root.appendingPathComponent("note.minote")
        let (document, urls) = try fixture(at: root)
        try await NoteBackup().export(document: document, assetURLs: urls, destination: archive)
        var raw = try Data(contentsOf: archive)
        let entries = try StoredZIP.index(archive)
        raw[Int(try XCTUnwrap(entries.first(where: { $0.name == "document.json" })).dataOffset)] ^= 1
        try raw.write(to: archive)
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do { _ = try await NoteBackup().validate(source: archive, stagingRoot: staging); XCTFail("expected CRC rejection") } catch { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
        var future = document; future.schemaVersion = 4
        do { try await NoteBackup().export(document: future, assetURLs: urls, destination: archive); XCTFail("expected future rejection") }
        catch { XCTAssertEqual(error as? DocumentError, .unsupportedSchema(4)) }
        XCTAssertEqual(try Data(contentsOf: archive), raw)
    }

    func testWellFormedZIPWithFutureDocumentOrWrongManifestIsRejected() async throws {
        let root = try LibraryTestSupport.directory(self), archive = root.appendingPathComponent("note.minote")
        let (document, urls) = try fixture(at: root)
        try await NoteBackup().export(document: document, assetURLs: urls, destination: archive)
        let previous = try Data(contentsOf: archive)
        let script = """
        import zipfile,json,zlib,sys
        from pathlib import Path
        r=Path(sys.argv[1]); src=zipfile.ZipFile(r/'note.minote'); original={n:src.read(n) for n in src.namelist()}
        for kind in ['future','length','missing']:
            entries=original.copy(); m=json.loads(entries['manifest.json'])
            if kind=='future':
                d=json.loads(entries['document.json']); d['schemaVersion']=4; m['schemaVersion']=4
                entries['document.json']=json.dumps(d).encode()
                e=next(e for e in m['entries'] if e['name']=='document.json'); e['byteCount']=len(entries['document.json']); e['crc32']=zlib.crc32(entries['document.json'])
            if kind=='length': m['entries'][0]['byteCount']+=1
            if kind=='missing': entries.pop(next(n for n in entries if n.startswith('assets/')))
            entries['manifest.json']=json.dumps(m).encode()
            with zipfile.ZipFile(r/(kind+'.minote'),'w') as out:
                for n,b in entries.items(): out.writestr(n,b)
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, root.path]; try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for kind in ["future", "length", "missing"] {
            do { _ = try await NoteBackup().validate(source: root.appendingPathComponent(kind + ".minote"), stagingRoot: staging); XCTFail(kind) }
            catch { if kind == "future" { XCTAssertEqual(error as? DocumentError, .unsupportedSchema(4)) } }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
        XCTAssertEqual(try Data(contentsOf: archive), previous)
    }
}
