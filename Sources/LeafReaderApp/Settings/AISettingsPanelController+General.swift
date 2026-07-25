import Cocoa
import SwiftUI

extension AISettingsPanelController {
    /// Fills the General page with the SwiftUI form.
    ///
    /// This is the AppKit↔SwiftUI bridge, kept deliberately small: one hosting
    /// view pinned to the page. Everything outside this page — the tab strip,
    /// Save and Cancel — remains AppKit.
    func installGeneralSettingsPage(in page: NSView) {
        // Theme and brightness apply live, so both the reader *and* the panel
        // the switch was flipped in have to restyle. The AppKit handler this
        // replaced did the panel half itself; forgetting it here left the open
        // panel showing the previous theme until it was reopened.
        let model = GeneralSettingsModel { [weak self] in
            guard let self else { return }
            self.applySettingsPanelTheme(ReaderTheme.selected)
            self.onAppearanceChanged?()
        }
        generalSettings = model

        installSettingsPage(GeneralSettingsView(model: model), in: page)
    }
}
