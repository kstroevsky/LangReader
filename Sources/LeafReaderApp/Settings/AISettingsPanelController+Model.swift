import Cocoa
import SwiftUI

extension AISettingsPanelController {
    /// Fills the Model page with the SwiftUI form.
    ///
    /// Same shape as the General page: one hosting view pinned to the page,
    /// with the tab strip, Save and Cancel left alone.
    func installModelSettingsPage(in page: NSView) {
        let model = ModelSettingsModel()
        model.onTestConnection = { [weak self] in
            self?.testChatConnection()
        }
        modelSettings = model

        installSettingsPage(ModelSettingsView(model: model), in: page)
    }

    /// Fills the AI Analysis page with the SwiftUI form.
    func installEmbeddingSettingsPage(in page: NSView) {
        let model = EmbeddingSettingsModel()
        model.onTestConnection = { [weak self] in
            self?.testEmbeddingConnection()
        }
        embeddingSettings = model

        installSettingsPage(EmbeddingSettingsView(model: model), in: page)
    }
}
