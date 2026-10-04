import Foundation
import XCTest
@testable import MiNoteCore

@MainActor final class StoredZIPTests: XCTestCase {
    func testCRCMatchesIndependentStandardVector() {
        var crc = CRC32(); crc.update(Data("123456789".utf8)); XCTAssertEqual(crc.value, 0xcbf43926)
    }

    func testMalformedArchiveNeverEscapesStaging() throws {
        let root = try LibraryTestSupport.directory(self), sentinel = root.appendingPathComponent("sentinel")
        try Data("untouched".utf8).write(to: sentinel)
        // Independent ZIP producer exercises unsafe paths/entry kinds and header agreement.
        let script = """
        import zipfile,sys,struct
        from pathlib import Path
        r=Path(sys.argv[1])
        cases=['../sentinel','/sentinel','assets\\\\evil.pdf','duplicate','symlink','deflate']
        for n,c in enumerate(cases):
            with zipfile.ZipFile(r/f'{n}.zip','w') as z:
                name=c if n<3 else 'document.json'
                i=zipfile.ZipInfo(name)
                if c=='symlink': i.create_system=3; i.external_attr=(0o120777<<16)
                if c=='deflate': i.compress_type=8
                z.writestr(i,b'abc')
                if c=='duplicate': z.writestr(i,b'def')
        with zipfile.ZipFile(r/'valid.zip','w') as z: z.writestr('document.json',b'abc')
        a=bytearray((r/'valid.zip').read_bytes()); c=a.index(b'PK\\x01\\x02'); e=a.index(b'PK\\x05\\x06')
        mods=[(6,1),(6,8),(18,0xffffffff),(c+10,8),(c+42,1),(e+16,1),(14,123)]
        for n,(offset,value) in enumerate(mods,6):
            b=a.copy(); struct.pack_into('<H' if offset in [6,c+10] else '<I',b,offset,value); (r/f'{n}.zip').write_bytes(b)
        (r/'13.zip').write_bytes(a[:-1])
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, root.path]; try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let valid = root.appendingPathComponent("valid.zip")
        let entries = try StoredZIP.index(valid)
        XCTAssertEqual(try StoredZIP.read(entries[0], from: valid, limit: 128), Data("abc".utf8))
        for index in 0..<14 {
            XCTAssertThrowsError(try StoredZIP.index(root.appendingPathComponent("\(index).zip")), "case \(index)")
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("untouched".utf8))
    }
}
