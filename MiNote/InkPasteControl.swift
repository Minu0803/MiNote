import SwiftUI
import UIKit

/// UIKit grants paste access for the user's action. App code never polls the clipboard.
struct InkPasteControl: UIViewRepresentable {
    let isEnabled: Bool
    let onPaste: ([NSItemProvider]) -> Void
    func makeCoordinator() -> Target { Target(onPaste: onPaste) }
    func makeUIView(context: Context) -> UIPasteControl {
        let config = UIPasteControl.Configuration(); config.displayMode = .iconOnly
        let control = UIPasteControl(configuration: config)
        control.target = context.coordinator
        control.accessibilityIdentifier = "pasteSelectedInk"
        control.accessibilityLabel = "붙여넣기"
        return control
    }
    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
        context.coordinator.isEnabled = isEnabled
        control.isUserInteractionEnabled = isEnabled
        control.alpha = isEnabled ? 1 : 0.4
        control.accessibilityTraits = isEnabled ? [.button] : [.button, .notEnabled]
    }
    final class Target: NSObject, UIPasteConfigurationSupporting {
        var pasteConfiguration: UIPasteConfiguration? = UIPasteConfiguration(acceptableTypeIdentifiers: [InkClipboardAccess.typeIdentifier])
        var onPaste: ([NSItemProvider]) -> Void
        var isEnabled = true
        init(onPaste: @escaping ([NSItemProvider]) -> Void) { self.onPaste = onPaste }
        func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            isEnabled && itemProviders.count == 1 && itemProviders[0].hasItemConformingToTypeIdentifier(InkClipboardAccess.typeIdentifier)
        }
        func paste(itemProviders: [NSItemProvider]) { guard isEnabled else { return }; onPaste(itemProviders) }
    }
}
