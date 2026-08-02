import SwiftUI
import LeafReaderCore

/// The Read Aloud settings page: which TTS runtime, voice and speed to use,
/// then one row per runtime showing whether it is installed, downloading or
/// absent.
///
/// The runtime rows are the shared `SettingsStatusRow` with a progress bar —
/// the same component the Cache page's rows use.
struct SpeechSettingsView: View {
    @Bindable var model: SpeechSettingsModel

    var body: some View {
        Form {
            Section {
                Picker(AppText.localized("朗读模型", "TTS Model"), selection: $model.runtimeID) {
                    ForEach(model.runtimeOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .accessibilityIdentifier(SpeechSettingsAccessibility.runtimePicker)

                Picker(AppText.localized("声音", "Voice"), selection: $model.voiceID) {
                    ForEach(model.voiceOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .accessibilityIdentifier(SpeechSettingsAccessibility.voicePicker)

                Picker(AppText.localized("语速", "Speed"), selection: $model.speedID) {
                    ForEach(model.speedOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .accessibilityIdentifier(SpeechSettingsAccessibility.speedPicker)
            }

            ForEach(model.runtimes) { row in
                Section {
                    SettingsStatusRow(
                        title: row.title,
                        status: row.status,
                        progress: row.progress,
                        actions: model.actions(for: row)
                    )
                }
            }

            Section {
                SettingsStatusRow(
                    title: AppText.localized("诊断", "Diagnostics"),
                    status: AppText.localized(
                        "复制朗读模型的安装与运行信息，便于反馈问题。",
                        "Copy the TTS runtimes' install and run details for a bug report."
                    ),
                    actions: [model.diagnosticsAction]
                )
            }
        }
        .settingsFormStyle()
    }
}
