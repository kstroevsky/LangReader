import Cocoa
import SwiftUI
import LeafReaderCore

@MainActor
final class VocabularyPreparationPanelController: NSObject, NSWindowDelegate {
    private let coordinator: VocabularyPreparationCoordinator
    private(set) var window: NSWindow?

    init(coordinator: VocabularyPreparationCoordinator) {
        self.coordinator = coordinator
    }

    func present() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        coordinator.cancel()
    }

    private func buildWindow() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.localized("阅读前词汇准备", "Prepare Vocabulary")
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 820, height: 620)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: VocabularyPreparationView(coordinator: coordinator))
        panel.center()
        window = panel
    }
}
