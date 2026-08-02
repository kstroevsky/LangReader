import Cocoa
import LeafReaderCore

@MainActor
final class VocabularyPanelController {
    weak var owner: ReaderWindowController?
    private(set) weak var panel: NSWindow?
    private let reloadTask = DebouncedTask(delay: 0.04)
    /// State behind the SwiftUI header. Held here so the summary and the stats
    /// are updated by assignment rather than by searching the view tree for a
    /// label with a matching identifier.
    let headerModel = VocabularyTrainerHeaderModel()
    /// State behind the SwiftUI word list.
    let listModel = VocabularyWordListModel()
    private var activationObserver: NSObjectProtocol?

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    deinit {
        MainActor.assumeIsolated {
            reloadTask.cancel()
            removeActivationObserver()
        }
    }

    var rootView: NSView? {
        panel?.contentView
    }

    func show(records: [VocabularyExportRecord]) {
        guard let panel = makePanel(records: records) else { return }
        present(panel)
    }

    func present(_ panel: NSWindow) {
        self.panel = panel
        owner?.reloadVocabularyPanelContent()
        installActivationObserver()
        ModalOverlayManager.shared.present(panel, attachedTo: owner?.window)
    }

    func close() {
        guard let panel else { return }
        owner?.commitPendingVocabularyAnswerIfNeeded()
        removeActivationObserver()
        ModalOverlayManager.shared.dismiss(panel, attachedTo: owner?.window)
        self.panel = nil
    }

    func scheduleReload() {
        reloadTask.schedule { [weak self] in
            self?.owner?.reloadVocabularyPanelContent()
        }
    }

    private func installActivationObserver() {
        removeActivationObserver()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let panel = self?.panel else { return }
                ModalOverlayManager.shared.reactivate(panel)
            }
        }
    }

    private func removeActivationObserver() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

}
