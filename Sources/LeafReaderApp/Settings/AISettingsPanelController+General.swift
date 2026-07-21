import Cocoa
import SwiftUI

extension AISettingsPanelController {
    /// Fills the General page with the SwiftUI form.
    ///
    /// This is the AppKit↔SwiftUI bridge, kept deliberately small: one hosting
    /// view pinned to the page. Everything outside this page — the tab strip,
    /// Save and Cancel — remains AppKit.
    func installGeneralSettingsPage(in page: NSView) {
        let model = GeneralSettingsModel { [weak self] in
            self?.onAppearanceChanged?()
        }
        generalSettings = model

        let hosting = NSHostingView(rootView: GeneralSettingsView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: page.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: page.bottomAnchor)
        ])
    }
}
