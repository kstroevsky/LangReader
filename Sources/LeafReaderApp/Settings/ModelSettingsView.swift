import SwiftUI

/// The Model settings page: which chat model to use, its endpoint and model
/// name where those are configurable, and the API key.
///
/// The page is the shared `AIServiceSection` and nothing else — the AI Analysis
/// page is the same shape, so everything that used to be written out here lives
/// in the section and everything that differs comes from the model.
struct ModelSettingsView: View {
    @Bindable var model: ModelSettingsModel

    var body: some View {
        Form {
            AIServiceSection(model: model)
        }
        .settingsFormStyle()
        .animation(.default, value: model.showsEndpointField)
        .animation(.default, value: model.showsModelNameField)
    }
}
