import SwiftUI

/// The Cache settings page: the current book's AI analysis data, and the
/// machine-wide analysis cache.
///
/// Both are the shared `SettingsStatusRow` — a title, a live status line and a
/// row of actions — so the page is two rows of data.
struct CacheSettingsView: View {
    @Bindable var model: CacheSettingsModel

    var body: some View {
        Form {
            Section {
                SettingsStatusRow(
                    title: AppText.localized("当前书 AI 分析数据", "Current Book AI Analysis Data"),
                    status: model.currentBookStatus,
                    actions: model.currentBookActions
                )
            }

            Section {
                SettingsStatusRow(
                    title: AppText.localized("AI 分析缓存", "AI Analysis Cache"),
                    status: model.cacheStatus,
                    actions: model.allCacheActions
                )
            }
        }
        .settingsFormStyle()
    }
}
