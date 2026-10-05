import MiNoteCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: EditorSession
    @StateObject private var canvasReference = CanvasReference()
    @AppStorage("fingerDrawingEnabled") private var fingerDrawingEnabled =
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    @State private var exportedFile: ExportedFile?
    @State private var previewLease: UUID?
    @State private var backupTask: Task<Void, Never>?
    @State private var showsPageManager = false
    @State private var showsPDFImporter = false
    @State private var brush: Brush = .pen
    @State private var colorIndex = 1
    @State private var width = 3.0

    private let palette: [(name: String, color: Color, uiColor: UIColor)] = [
        ("검정", .primary, UIColor.label),
        ("파랑", Color(red: 0.20, green: 0.35, blue: 0.88), UIColor(red: 0.20, green: 0.35, blue: 0.88, alpha: 1)),
        ("빨강", Color(red: 0.84, green: 0.20, blue: 0.24), UIColor(red: 0.84, green: 0.20, blue: 0.24, alpha: 1)),
        ("초록", Color(red: 0.08, green: 0.48, blue: 0.35), UIColor(red: 0.08, green: 0.48, blue: 0.35, alpha: 1)),
        ("주황", Color(red: 0.91, green: 0.43, blue: 0.10), UIColor(red: 0.91, green: 0.43, blue: 0.10, alpha: 1))
    ]

    private let onClose: () -> Void
    init(session: EditorSession, onClose: @escaping () -> Void) {
        _session = StateObject(wrappedValue: session)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            if session.document == nil {
                loadState
            } else {
                editor
            }
        }
        .task { await session.loadIfNeeded() }
        .fileImporter(isPresented: $showsPDFImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): Task { await session.importPDF(from: url) }
            case .failure(let error): session.operationError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsPageManager) {
            PageManagerView(session: session) { showsPageManager = false }
        }
        .sheet(item: $exportedFile, onDismiss: {
            if let lease = previewLease { Task { try? await session.exportRegistry.release(lease) } }; previewLease = nil
        }) { file in
            ExportPreview(file: file, registry: session.exportRegistry) { exportedFile = nil }
        }
        .alert("문서 작업을 완료하지 못했습니다", isPresented: Binding(
            get: { session.operationError != nil && !showsPageManager }, set: { if !$0 { session.operationError = nil } })) {
            Button("확인") { session.operationError = nil }
        } message: { Text(session.operationError ?? "") }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .inactive || phase == .background else { return }
            captureDrawing()
            let lease = BackgroundSaveLease()
            Task {
                await session.flush()
                lease.end()
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: brush) { _, value in if value != .lasso { session.clearInkSelection() } }
    }

    private var loadState: some View {
        VStack(spacing: 20) {
            Image(systemName: session.loadError == nil ? "doc.text" : "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .light)).foregroundStyle(Color.accentColor)
            if let error = session.loadError {
                Text("노트를 열 수 없습니다").font(.title2.weight(.semibold))
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("다시 시도") { Task { await session.retryLoad() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retryLoad")
            } else {
                ProgressView("노트를 여는 중")
            }
        }
        .padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var editor: some View {
        VStack(spacing: 0) {
            header
            documentBar
            if let notice = session.recoveryNotice {
                Label(notice, systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
            }
            if case .failed = session.saveState {
                HStack(spacing: 12) {
                    Label(session.saveStatusLabel, systemImage: "exclamationmark.circle.fill").lineLimit(2)
                    Spacer(minLength: 0)
                    Button("재시도") { session.retrySave() }.buttonStyle(.bordered)
                        .accessibilityIdentifier("retrySave")
                }
                .font(.footnote).padding(.horizontal, 20).padding(.vertical, 8)
                .background(Color.red.opacity(0.10)).foregroundStyle(Color.red)
            }
            NoteCanvas(session: session, reference: canvasReference, tool: brush,
                       color: palette[colorIndex].uiColor, width: width,
                       fingerDrawingEnabled: fingerDrawingEnabled)
                .id(session.canvasGeneration)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .overlay {
                    if session.isProcessing {
                        BackupProgressView(progress: session.operationProgress, cancel: backupTask == nil ? nil : { backupTask?.cancel() })
                    }
                }
            toolbar
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var documentBar: some View {
        HStack(spacing: 16) {
            Button { captureDrawing(); Task { await session.selectPage(session.currentPageIndex - 1) } } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("이전 페이지").accessibilityIdentifier("previousPage")
            .disabled(session.currentPageIndex == 0 || session.isProcessing)
            Text("\(session.currentPageIndex + 1) / \(session.document?.pages.count ?? 1)")
                .font(.caption.monospacedDigit()).accessibilityIdentifier("pageIndicator")
            Button { captureDrawing(); Task { await session.selectPage(session.currentPageIndex + 1) } } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("다음 페이지").accessibilityIdentifier("nextPage")
            .disabled(session.currentPageIndex + 1 >= (session.document?.pages.count ?? 1) || session.isProcessing)
            Text(session.currentPage?.pdfSource == nil ? (session.currentPage?.paper.title ?? "") : "PDF")
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("paperStyle")
            if brush == .lasso {
                Text("선택 \(session.selectedStrokeIDs.count)획").font(.caption.monospacedDigit())
                    .accessibilityIdentifier("selectionCount")
                Button { canvasReference.deleteSelectedInk(in:session) } label: { Image(systemName:"trash") }
                    .accessibilityLabel("선택 삭제").accessibilityIdentifier("deleteSelectedInk")
                    .disabled(!session.canApplyInkCommand || session.selectedStrokeIDs.isEmpty)
                Button { canvasReference.duplicateSelectedInk(in:session) } label: { Image(systemName:"plus.square.on.square") }
                    .accessibilityLabel("복제").accessibilityIdentifier("duplicateSelectedInk")
                    .disabled(!session.canApplyInkCommand || session.selectedStrokeIDs.isEmpty)
                Button("선택 해제") { session.clearInkSelection() }
                    .accessibilityIdentifier("clearSelection").disabled(session.isProcessing || session.selectedStrokeIDs.isEmpty)
            }
            Spacer()
            Button { captureDrawing(); showsPageManager = true } label: { Image(systemName: "square.grid.2x2") }
                .accessibilityLabel("페이지 관리").accessibilityIdentifier("pageManager").disabled(session.isProcessing)
            Button { captureDrawing(); showsPDFImporter = true } label: { Label("PDF 가져오기", systemImage: "doc.badge.plus") }
                .accessibilityIdentifier("importPDF")
                .disabled(session.isProcessing)
            Button {
                captureDrawing()
                Task { if let file = await session.exportPDF() { previewLease = file.lease; exportedFile = file } }
            } label: { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel("PDF 내보내기").accessibilityIdentifier("exportPDF")
            .disabled(session.isProcessing)
            Button {
                guard backupTask == nil else { return }
                captureDrawing()
                backupTask = Task {
                    if let file = await session.exportBackup() { previewLease = file.lease; exportedFile = file }
                    backupTask = nil
                }
            } label: { Image(systemName: "doc.zipper") }
            .accessibilityLabel("편집 원본 백업").accessibilityIdentifier("exportBackup").disabled(session.isProcessing || backupTask != nil)
        }
        .font(.callout).padding(.horizontal, 26).padding(.vertical, 10).background(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                captureDrawing()
                onClose()
            } label: { Label("라이브러리", systemImage: "chevron.left") }
            .accessibilityIdentifier("closeNote").disabled(session.isProcessing)
            VStack(alignment: .leading, spacing: 3) {
                Text("MiNote").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Color(red: 0.14, green: 0.18, blue: 0.25))
                Text(session.document?.title ?? "노트").lineLimit(1).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(session.saveStatusLabel, systemImage: saveSymbol)
                .font(.caption.weight(.medium)).foregroundStyle(saveTint)
                .lineLimit(1).accessibilityIdentifier("saveStatus")
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 30)
            Button { canvasReference.undo(in: session) } label: { Image(systemName: "arrow.uturn.backward") }
                .accessibilityLabel("실행 취소").accessibilityIdentifier("undo")
                .disabled(!canvasReference.canUndo || !session.canReplayInkHistory)
            Button { canvasReference.redo(in: session) } label: { Image(systemName: "arrow.uturn.forward") }
                .accessibilityLabel("다시 실행").accessibilityIdentifier("redo")
                .disabled(!canvasReference.canRedo || !session.canReplayInkHistory)
            Text("획 \(session.strokeCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(.white, in: Capsule()).foregroundStyle(.secondary)
                .accessibilityIdentifier("strokeCount")
        }
        .buttonStyle(.plain).padding(.horizontal, 26).padding(.vertical, 14)
        .background(.white.opacity(0.96))
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                toolButton(.pen, symbol: "pencil.tip.crop.circle", title: "펜")
                toolButton(.marker, symbol: "highlighter", title: "형광펜")
                toolButton(.eraser, symbol: "eraser", title: "획 지우개")
                toolButton(.lasso, symbol: "lasso", title: "올가미")
            }
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 34)
            HStack(spacing: 10) {
                ForEach(palette.indices, id: \.self) { index in
                    Button { colorIndex = index; if brush == .eraser || brush == .lasso { brush = .pen } } label: {
                        Circle().fill(palette[index].color).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.white, lineWidth: 2).padding(2))
                            .padding(3)
                            .overlay(Circle().stroke(colorIndex == index ? Color(red: 0.20, green: 0.37, blue: 0.82) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain).accessibilityLabel("색상 \(palette[index].name)")
                }
            }
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 34)
            HStack(spacing: 9) {
                Image(systemName: "circle.fill").font(.system(size: 5 + width)).foregroundStyle(palette[colorIndex].color)
                    .frame(width: 22, height: 24)
                Slider(value: $width, in: 1...10, step: 0.5).frame(width: 112)
                    .tint(Color(red: 0.20, green: 0.37, blue: 0.82))
                    .accessibilityLabel("획 굵기")
                Text("\(width, specifier: "%.1f")").font(.caption2.monospacedDigit()).frame(width: 26, alignment: .trailing)
            }
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 34)
            Toggle(isOn: $fingerDrawingEnabled) {
                Label("손가락", systemImage: "hand.draw")
                    .font(.caption.weight(.medium))
            }
            .toggleStyle(.switch).fixedSize().accessibilityIdentifier("fingerDrawing")
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.055), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 3)
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
        }
        .frame(height: 96)
        .accessibilityIdentifier("inkToolbar")
        .disabled(session.isProcessing)
    }

    private func captureDrawing() {
        canvasReference.captureDrawing(in:session)
    }

    private func toolButton(_ value: Brush, symbol: String, title: String) -> some View {
        Button { brush = value } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium)).labelStyle(.titleAndIcon)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .foregroundStyle(brush == value ? Color.white : Color.primary.opacity(0.75))
                .background(brush == value ? Color(red: 0.17, green: 0.23, blue: 0.37) : .clear,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityIdentifier("tool-\(value.rawValue)")
    }

    private var saveSymbol: String {
        switch session.saveState {
        case .saving: "arrow.triangle.2.circlepath"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var saveTint: Color {
        switch session.saveState {
        case .saving: .secondary
        case .saved: Color(red: 0.12, green: 0.50, blue: 0.34)
        case .failed: .red
        }
    }
}

@MainActor
private final class BackgroundSaveLease {
    private var identifier = UIBackgroundTaskIdentifier.invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "MiNoteDocumentSave") { [weak self] in
            Task { @MainActor [weak self] in self?.end() }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
