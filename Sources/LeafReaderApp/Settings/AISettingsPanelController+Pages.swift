import Cocoa
import SwiftUI

extension AISettingsPanelController {
    /// Fills a settings page with a SwiftUI view.
    ///
    /// This is the whole AppKit↔SwiftUI bridge for every migrated page: one
    /// hosting view pinned to the page. The panel around it — tab strip, Save,
    /// Cancel — stays AppKit, so pages can migrate one at a time.
    func installSettingsPage<Content: View>(_ view: Content, in page: NSView) {
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: page.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: page.bottomAnchor)
        ])
    }

    /// Every migrated page, in tab order. Save validates and commits these
    /// without knowing what they are, so adding a page means adding it here and
    /// nowhere else.
    var settingsPages: [SettingsPage] {
        let pages: [SettingsPage?] = [generalSettings, modelSettings, embeddingSettings]
        return pages.compactMap { $0 }
    }
}
