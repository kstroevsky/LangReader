import SwiftUI

/// The General settings page.
///
/// The first screen migrated to SwiftUI. It renders inside the existing AppKit
/// settings panel through an `NSHostingView`, so the panel's tabs, Save and
/// Cancel keep working exactly as before — the migration replaces one page, not
/// the window.
struct GeneralSettingsView: View {
    @Bindable var model: GeneralSettingsModel

    var body: some View {
        Form {
            Section {
                Picker(AppText.localized("界面语言", "Interface Language"), selection: $model.language) {
                    ForEach(AppText.Language.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                .accessibilityIdentifier(GeneralSettingsAccessibility.languagePicker)
                SettingsFootnote(AppText.localized("更改后界面文字会立即更新。", "Interface text updates as soon as you save."))
            }

            Section {
                Picker(AppText.localized("阅读主题", "Reading Theme"), selection: $model.theme) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .accessibilityIdentifier(GeneralSettingsAccessibility.themePicker)
                SettingsFootnote(ReaderTheme.selected.helpText)

                // Brightness only means something once the page is tinted.
                if model.showsBrightness {
                    LabeledContent(AppText.localized("阅读区亮度", "Reading Area Brightness")) {
                        Slider(value: $model.brightness, in: model.brightnessRange) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "sun.min")
                        } maximumValueLabel: {
                            Image(systemName: "sun.max")
                        }
                        .frame(minWidth: 220)
                        .accessibilityIdentifier(GeneralSettingsAccessibility.brightnessSlider)
                    }
                }
            }

            Section {
                Toggle(AppText.localized("自动播放单词", "Auto Play Words"), isOn: $model.speaksSelectedWord)
                    .accessibilityIdentifier(GeneralSettingsAccessibility.speakWordToggle)
                Toggle(AppText.localized("保存 AI 对话", "Save AI Conversations"), isOn: $model.savesAIConversation)
                    .accessibilityIdentifier(GeneralSettingsAccessibility.saveConversationToggle)
            }
        }
        .settingsFormStyle()
        .animation(.default, value: model.showsBrightness)
    }
}
