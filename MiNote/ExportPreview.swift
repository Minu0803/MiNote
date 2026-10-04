import SwiftUI
import UIKit

struct ExportPreview: View {
    let file: ExportedFile
    let registry: ExportFileRegistry
    let onClose: () -> Void
    @State private var share: ShareRequest?
    @State private var error: String?
    @State private var isPreparingShare = false
    var body: some View {
        VStack(spacing: 16) {
            Text(file.isBackup ? "편집 원본 백업" : "필기를 포함한 PDF").font(.headline)
            Text(file.isBackup ? "필기·용지·책갈피·삭제 보관 페이지와 PDF 원본을 담았습니다. 파일에 저장한 뒤 MiNote에서 새 노트로 복원할 수 있습니다. 실행 취소 기록은 포함하지 않습니다." : "필기는 이미지로 고정되고 PDF 양식·주석은 수정할 수 없게 됩니다. 일부 링크는 유지되지 않을 수 있습니다.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if file.isBackup {
                Image(systemName: "doc.zipper").font(.system(size: 64)).foregroundStyle(.blue).frame(maxHeight: .infinity)
            } else { PDFPreview(url: file.url) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            HStack {
                Button("닫기", action: onClose).buttonStyle(.bordered).accessibilityIdentifier("closeExportPreview").disabled(isPreparingShare)
                Button {
                    guard !isPreparingShare, share == nil else { return }
                    isPreparingShare = true
                    Task {
                        defer { isPreparingShare = false }
                        do { share = ShareRequest(file: file, lease: try await registry.acquire(file)) }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { Label("공유·파일에 저장", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent).accessibilityIdentifier(file.isBackup ? "shareBackup" : "sharePDF")
                .disabled(isPreparingShare || share != nil)
            }
        }.padding(24)
        .interactiveDismissDisabled(isPreparingShare)
        .sheet(item: $share) { request in
            ShareController(file: request.file, lease: request.lease, registry: registry) { share = nil }
        }
    }
}
private struct ShareRequest: Identifiable { var id: UUID { lease }; let file: ExportedFile; let lease: UUID }
private struct ShareController: UIViewControllerRepresentable {
    let file: ExportedFile
    let lease: UUID
    let registry: ExportFileRegistry
    let onComplete: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(lease: lease, registry: registry, onComplete: onComplete) }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, _ in coordinator.complete() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) { coordinator.complete() }
    @MainActor final class Coordinator {
        let lease: UUID
        let registry: ExportFileRegistry
        let onComplete: () -> Void
        private var completed = false
        init(lease: UUID, registry: ExportFileRegistry, onComplete: @escaping () -> Void) { self.lease = lease; self.registry = registry; self.onComplete = onComplete }
        func complete() {
            guard !completed else { return }; completed = true
            Task { try? await registry.release(lease); onComplete() }
        }
    }
}
