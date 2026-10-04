import MiNoteCore
import SwiftUI

struct BackupProgressView: View {
    let progress: BackupProgress?
    let cancel: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            if let progress, progress.totalBytes > 0 {
                ProgressView("백업 처리 중", value: Double(progress.completedBytes), total: Double(progress.totalBytes))
                    .frame(width: 220)
                Text("\(Int(min(1, Double(progress.completedBytes) / Double(progress.totalBytes)) * 100))%")
                    .font(.caption.monospacedDigit())
            } else { ProgressView("문서 처리 중") }
            if let cancel { Button("취소", action: cancel).accessibilityIdentifier("cancelBackupOperation") }
        }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct StorageMaintenanceView: View {
    @ObservedObject var session: LibrarySession
    let onClose: () -> Void
    @State private var confirmsCleanup = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("현재 문서와 정상 복구본에서 쓰는 PDF는 보존합니다. 문서 확인에 문제가 있으면 그 노트의 정리를 보류합니다.")
                    if let report = session.maintenanceReport {
                        Text("미사용 PDF \(report.candidates.count)개 · \(ByteCountFormatter.string(fromByteCount: report.candidateBytes, countStyle: .file))")
                        Text("이번 정리: PDF \(report.removedURLs.count)개, 7일 지난 공유 파일 묶음 \(session.cleanedExports)개")
                            .accessibilityIdentifier("cleanupResult")
                        Button("미사용 파일 정리") { confirmsCleanup = true }.disabled(session.isBusy).accessibilityIdentifier("cleanStorage")
                    } else { ProgressView("저장 공간 확인 중") }
                }
                if let report = session.maintenanceReport, !report.protectedItems.isEmpty {
                    Section("보호·보류 이유") {
                        ForEach(Array(Set(report.protectedItems.compactMap(\.protectionReason))).sorted(), id: \.self) { Text($0).font(.footnote) }
                    }
                }
                Section { Text("미리보기·공유 중인 파일과 앱 중단 시 사용 중이던 공유 파일은 보호합니다. 폴더 전체 백업과 클라우드 동기화는 제공하지 않습니다.").font(.footnote).foregroundStyle(.secondary) }
                if let error = session.operationError { Text(error).foregroundStyle(.red).font(.footnote) }
            }.navigationTitle("저장 공간 정리")
                .toolbar { Button("닫기", action: onClose).disabled(session.isBusy).accessibilityIdentifier("closeStorage") }
                .task { await session.inspectMaintenance() }
                .alert("미사용 파일을 정리할까요?", isPresented: $confirmsCleanup) {
                    Button("취소", role: .cancel) {}
                    Button("정리", role: .destructive) { Task { await session.cleanStorage() } }.accessibilityIdentifier("confirmCleanup")
                } message: { Text("문서와 복구본에서 사용하지 않는 PDF 및 사용이 끝난 7일 지난 공유 파일만 제거합니다.") }
        }.interactiveDismissDisabled(session.isBusy)
    }
}
