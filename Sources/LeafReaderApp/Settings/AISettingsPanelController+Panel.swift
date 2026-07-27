import Cocoa
import LeafReaderCore

extension AISettingsPanelController {
    func showPanel(_ panel: NSWindow, attachedTo parent: NSWindow) {
        ModalOverlayManager.shared.present(panel, attachedTo: parent)
    }

    func installAppActivationObserver() {
        removeAppActivationObserver()
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.reactivatePanelIfNeeded()
        }
    }

    func removeAppActivationObserver() {
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    func reactivatePanelIfNeeded() {
        guard let panel, panel.isVisible else { return }
        ModalOverlayManager.shared.reactivate(panel)
    }

    @objc func save(_ sender: NSButton) {
        guard let panel else { return }
        guard saveCurrentSettings(in: panel) else { return }
        closePanel(notifySaved: true)
    }

    func saveCurrentSettings(in panel: NSWindow) -> Bool {
        // Migrated pages own their own settings: validate them all before
        // committing any, so a rejected page cannot leave a half-saved panel.
        let pages = settingsPages
        for page in pages {
            if let error = page.validationError() {
                showValidationAlert(message: error, in: panel)
                return false
            }
        }
        pages.forEach { $0.commit() }
        return true
    }

    @objc func cancel(_ sender: NSButton) {
        closePanel(notifySaved: false)
    }

    @objc func settingsSegmentChanged(_ sender: NSSegmentedControl) {
        settingsTabChanged(index: sender.selectedSegment)
    }

    func settingsTabChanged(index: Int) {
        (settingsTabControl as? SettingsTabsView)?.selectIndex(index)
        (settingsSidebarControl as? SettingsTabsView)?.selectIndex(index)
        basicPage?.isHidden = index != 0
        modelPage?.isHidden = index != 1
        embeddingPage?.isHidden = index != 2
        speechPage?.isHidden = index != 3
        cachePage?.isHidden = index != 4
        cacheSettings?.refresh(currentBookStatus: currentVectorIndexStatus?() ?? AppText.noPDF)
        if index == 4 {
            refreshVectorCacheStatus()
        }
        if let scrollView = settingsScrollView {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scrollView.verticalScrollElasticity = .none
            scrollView.hasVerticalScroller = false
        }
    }
}
