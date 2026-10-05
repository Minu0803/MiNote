import Foundation
import MiNoteCore
import UIKit

@MainActor final class InkClipboardAccess {
    nonisolated static let typeIdentifier = "com.minote.ink-selection"
    private let pasteboard: UIPasteboard
    init(pasteboard: UIPasteboard = .general) { self.pasteboard = pasteboard }
    func write(_ data: Data) throws {
        _ = try InkClipboardCodec.decode(data)
        pasteboard.setItems([[Self.typeIdentifier: data]], options: [.localOnly: true])
    }
    func read(from providers: [NSItemProvider]) async throws -> Data {
        try Task.checkCancellation()
        guard providers.count == 1, let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(Self.typeIdentifier) else {
            throw DocumentError.invalidDocument("MiNote 필기 한 항목을 붙여넣어 주세요.")
        }
        let read = InkProviderRead()
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard read.begin(continuation) else { return }
                let progress = provider.loadDataRepresentation(forTypeIdentifier: Self.typeIdentifier) { data, error in
                    if let data {
                        guard data.count <= InkClipboardCodec.maximumBytes else { read.finish(.failure(DocumentError.invalidDocument("붙여넣기 용량 한도"))); return }
                        read.finish(.success(data)); return
                    }
                    // Some providers only advertise a file representation. Read while its URL is valid.
                    let fileProgress = provider.loadFileRepresentation(forTypeIdentifier: Self.typeIdentifier) { url, fileError in
                        guard let url else { read.finish(.failure(fileError ?? error ?? DocumentError.corruptDocument)); return }
                        do {
                            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                            let bytes = try handle.read(upToCount: InkClipboardCodec.maximumBytes + 1) ?? Data()
                            guard bytes.count <= InkClipboardCodec.maximumBytes else { throw DocumentError.invalidDocument("붙여넣기 용량 한도") }
                            read.finish(.success(bytes))
                        } catch { read.finish(.failure(error)) }
                    }
                    read.install(fileProgress)
                }
                read.install(progress)
            }
        } onCancel: { read.cancel() }
        try Task.checkCancellation()
        _ = try InkClipboardCodec.decode(data)
        return data
    }
}

/// Cancellation and provider callbacks may race; exactly one resumes the request.
private final class InkProviderRead: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var progresses = [Progress]()
    private var ended = false
    func begin(_ c: CheckedContinuation<Data, Error>) -> Bool {
        let started = lock.withLock { if ended { return false }; continuation = c; return true }
        if !started { c.resume(throwing: CancellationError()) }
        return started
    }
    func install(_ progress: Progress) {
        let cancel = lock.withLock { if ended { return true }; progresses.append(progress); return false }
        if cancel { progress.cancel() }
    }
    func finish(_ result: Result<Data, Error>) {
        let c = lock.withLock { if ended { return nil as CheckedContinuation<Data, Error>? }; ended = true; let c = continuation; continuation = nil; return c }
        c?.resume(with: result)
    }
    func cancel() {
        let state = lock.withLock { ended = true; let c = continuation; continuation = nil; return (c, progresses) }
        state.0?.resume(throwing: CancellationError()); state.1.forEach { $0.cancel() }
    }
}
