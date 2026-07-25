import SwiftUI

/// The AI Analysis settings page: which embedding service to use, its endpoint
/// and model, the key, and whether new documents are indexed automatically.
///
/// The first three of those are the shared `AIServiceSection` — the same shape
/// as the Model page — so all this page adds is the auto-index switch.
struct EmbeddingSettingsView: View {
    @Bindable var model: EmbeddingSettingsModel

    var body: some View {
        Form {
            AIServiceSection(model: model)

            Section {
                Toggle(AppText.localized("自动 AI 缓存", "Auto AI Cache"), isOn: $model.autoIndexEnabled)
                    .accessibilityIdentifier(EmbeddingSettingsAccessibility.autoIndexToggle)
                Text(AppText.localized(
                    "打开后，新文档会在后台建立向量索引。",
                    "When on, new documents are indexed in the background."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .settingsFormStyle()
    }
}
