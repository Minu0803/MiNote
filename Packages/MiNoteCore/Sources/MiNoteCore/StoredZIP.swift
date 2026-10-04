import Foundation

public enum BackupError: Error, LocalizedError, Sendable, Equatable {
    case invalidArchive(String), limitExceeded, changedSource
    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let reason): "백업 파일을 확인할 수 없습니다: \(reason). 기존 기록을 보존합니다."
        case .limitExceeded: "백업 파일이 지원하는 용량 또는 항목 수를 초과했습니다."
        case .changedSource: "백업 도중 원본이 변경되었습니다. 다시 시도해 주세요."
        }
    }
}

struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0) }
        return value
    }
    private var state: UInt32 = 0xffffffff
    mutating func update(_ data: Data) { for byte in data { state = Self.table[Int((state ^ UInt32(byte)) & 255)] ^ (state >> 8) } }
    var value: UInt32 { state ^ 0xffffffff }
}

/// Deliberately limited ZIP32 profile. No path from an archive is used before this allowlist.
enum StoredZIP {
    static let chunkSize = 64 * 1024
    static let maximumBytes: UInt64 = 640 * 1024 * 1024
    static let jsonLimit = 128 * 1024 * 1024
    static let manifestLimit = 1024 * 1024
    static let entryLimit = 1002
    struct Source: Sendable { let name: String; let url: URL; let byteCount: UInt32; let crc32: UInt32 }
    struct Entry: Sendable { let name: String; let byteCount: UInt32; let crc32: UInt32; let dataOffset: UInt64 }

    static func allowed(_ name: String) -> Bool {
        if name == "manifest.json" || name == "document.json" { return true }
        guard name.hasPrefix("assets/"), name.hasSuffix(".pdf") else { return false }
        let value = String(name.dropFirst(7).dropLast(4))
        return UUID(uuidString: value)?.uuidString == value
    }
    static func size(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let count = attributes[.size] as? NSNumber else { throw BackupError.invalidArchive("일반 파일이 아닙니다") }
        return count.uint64Value
    }
    static func fingerprint(name: String, url: URL) throws -> Source {
        guard allowed(name) else { throw BackupError.invalidArchive("경로") }
        let expected = try size(url)
        let limit = name == "manifest.json" ? manifestLimit : name == "document.json" ? jsonLimit : 100 * 1024 * 1024
        guard expected <= UInt64(limit) else { throw BackupError.limitExceeded }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var crc = CRC32(), count: UInt64 = 0
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            try Task.checkCancellation(); count += UInt64(chunk.count)
            guard count <= expected else { throw BackupError.changedSource }; crc.update(chunk)
        }
        try Task.checkCancellation()
        guard count == expected else { throw BackupError.changedSource }
        return Source(name: name, url: url, byteCount: UInt32(count), crc32: crc.value)
    }
    static func write(_ sources: [Source], to url: URL,
                      writer: @Sendable (FileHandle, Data) throws -> Void,
                      progress: @Sendable (BackupProgress) -> Void) throws {
        guard sources.count <= entryLimit, Set(sources.map(\.name)).count == sources.count,
              sources.allSatisfy({ allowed($0.name) }) else { throw BackupError.invalidArchive("항목 수 또는 중복 경로") }
        let total = sources.reduce(Int64(0)) { $0 + Int64($1.byteCount) }
        let overhead = sources.reduce(UInt64(22)) { $0 + 76 + UInt64($1.name.utf8.count * 2) }
        guard UInt64(total) + overhead <= maximumBytes else { throw BackupError.limitExceeded }
        guard !FileManager.default.fileExists(atPath: url.path), FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw BackupError.invalidArchive("출력 임시 파일")
        }
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        var central = Data(), offset: UInt32 = 0, completed: Int64 = 0
        for source in sources {
            try Task.checkCancellation()
            let name = Data(source.name.utf8)
            var local = Data(); local.u32(0x04034b50); local.u16(10); local.u16(0x800); local.u16(0)
            local.u16(0); local.u16(0x21); local.u32(source.crc32); local.u32(source.byteCount); local.u32(source.byteCount)
            local.u16(UInt16(name.count)); local.u16(0); local.append(name); try writer(output, local)
            let input = try FileHandle(forReadingFrom: source.url); defer { try? input.close() }
            var count: UInt64 = 0, crc = CRC32()
            while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
                try Task.checkCancellation(); count += UInt64(data.count)
                guard count <= UInt64(source.byteCount) else { throw BackupError.changedSource }
                crc.update(data); try writer(output, data); completed += Int64(data.count)
                progress(BackupProgress(completedBytes: completed, totalBytes: total))
            }
            guard count == UInt64(source.byteCount), crc.value == source.crc32 else { throw BackupError.changedSource }
            central.u32(0x02014b50); central.u16(20); central.u16(10); central.u16(0x800); central.u16(0)
            central.u16(0); central.u16(0x21); central.u32(source.crc32); central.u32(source.byteCount); central.u32(source.byteCount)
            central.u16(UInt16(name.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0); central.u32(0); central.u32(offset)
            central.append(name); offset += UInt32(local.count) + source.byteCount
        }
        try Task.checkCancellation(); try writer(output, central)
        var end = Data(); end.u32(0x06054b50); end.u16(0); end.u16(0)
        end.u16(UInt16(sources.count)); end.u16(UInt16(sources.count)); end.u32(UInt32(central.count)); end.u32(offset); end.u16(0)
        try writer(output, end); try output.synchronize()
    }
    static func exact(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            guard let part = try handle.read(upToCount: min(chunkSize, count - result.count)), !part.isEmpty else {
                throw BackupError.invalidArchive("잘린 파일")
            }
            result.append(part)
        }
        return result
    }
    static func index(_ url: URL) throws -> [Entry] {
        let length = try size(url)
        guard length <= maximumBytes else { throw BackupError.limitExceeded }
        guard length >= 22 else { throw BackupError.invalidArchive("ZIP 끝") }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        try input.seek(toOffset: length - 22); let end = try exact(input, count: 22)
        let count = Int(end.v16(10)), centralSize = UInt64(end.v32(12)), centralOffset = UInt64(end.v32(16))
        guard end.v32(0) == 0x06054b50, end.v16(4) == 0, end.v16(6) == 0, end.v16(8) == end.v16(10),
              end.v16(20) == 0, count > 0, count <= entryLimit,
              centralOffset + centralSize == length - 22 else { throw BackupError.invalidArchive("ZIP32 목록") }
        var cursor = centralOffset, localCursor: UInt64 = 0, entries: [Entry] = [], names = Set<String>()
        for _ in 0..<count {
            guard cursor + 46 <= length - 22 else { throw BackupError.invalidArchive("목록 길이") }
            try input.seek(toOffset: cursor); let central = try exact(input, count: 46)
            let nameLength = Int(central.v16(28)), bytes = central.v32(24)
            let flags = central.v16(8), external = central.v32(38), mode = (external >> 16) & 0xf000
            guard central.v32(0) == 0x02014b50, central.v16(6) <= 20,
                  flags == 0 || flags == 0x800, central.v16(10) == 0,
                  central.v32(20) == bytes, bytes != UInt32.max,
                  central.v16(30) == 0, central.v16(32) == 0, central.v16(34) == 0,
                  (mode == 0 || mode == 0x8000), external & 0x10 == 0,
                  UInt64(central.v32(42)) == localCursor, nameLength > 0, nameLength <= 64,
                  cursor + 46 + UInt64(nameLength) <= length - 22 else { throw BackupError.invalidArchive("목록 헤더") }
            let nameData = try exact(input, count: nameLength)
            guard let name = String(data: nameData, encoding: .utf8), allowed(name), names.insert(name).inserted else {
                throw BackupError.invalidArchive("경로 또는 중복 항목")
            }
            let limit = name == "manifest.json" ? manifestLimit : name == "document.json" ? jsonLimit : 100 * 1024 * 1024
            guard bytes <= limit else { throw BackupError.limitExceeded }
            guard localCursor + 30 + UInt64(nameLength) + UInt64(bytes) <= centralOffset else { throw BackupError.invalidArchive("겹친 항목") }
            try input.seek(toOffset: localCursor); let local = try exact(input, count: 30)
            guard local.v32(0) == 0x04034b50, local.v16(4) == central.v16(6), local.v16(6) == flags,
                  local.v16(8) == 0, local.v16(10) == central.v16(12), local.v16(12) == central.v16(14),
                  local.v32(14) == central.v32(16), local.v32(18) == bytes, local.v32(22) == bytes,
                  local.v16(26) == nameLength, local.v16(28) == 0,
                  try exact(input, count: nameLength) == nameData else { throw BackupError.invalidArchive("local/central 불일치") }
            let dataOffset = localCursor + 30 + UInt64(nameLength)
            entries.append(Entry(name: name, byteCount: bytes, crc32: central.v32(16), dataOffset: dataOffset))
            localCursor = dataOffset + UInt64(bytes); cursor += 46 + UInt64(nameLength)
        }
        guard localCursor == centralOffset, cursor == length - 22 else { throw BackupError.invalidArchive("ZIP 경계") }
        return entries
    }
    static func consume(_ entry: Entry, from url: URL, body: (Data) throws -> Void) throws {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        try input.seek(toOffset: entry.dataOffset)
        var remaining = Int(entry.byteCount), crc = CRC32()
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try exact(input, count: min(chunkSize, remaining)); crc.update(data); try body(data); remaining -= data.count
        }
        guard crc.value == entry.crc32 else { throw BackupError.invalidArchive("CRC32 불일치: \(entry.name)") }
    }
    static func read(_ entry: Entry, from url: URL, limit: Int) throws -> Data {
        guard entry.byteCount <= limit else { throw BackupError.limitExceeded }
        var result = Data(); try consume(entry, from: url) { result.append($0) }; return result
    }
}

private extension Data {
    mutating func u16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func u32(_ value: UInt32) { u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(truncatingIfNeeded: value >> 16)) }
    func v16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func v32(_ offset: Int) -> UInt32 { UInt32(v16(offset)) | UInt32(v16(offset + 2)) << 16 }
}
