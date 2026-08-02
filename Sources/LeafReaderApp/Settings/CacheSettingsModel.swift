import Observation
import SwiftUI
import LeafReaderCore

/// State behind the Cache settings page.
///
/// Unlike the other pages nothing here is pending: every action takes effect
/// immediately, so there is nothing for Save to commit and the page is not a
/// `SettingsPage`. What it does have is *live* state — the cache size and the
/// current book's indexing progress both change while the panel is open — which
/// the panel refreshes on a timer by calling `refresh(...)`.
@Observable
final class CacheSettingsModel {
    /// "1.2 GB · 5 books · Auto-cleans over 1GB", or a reason it is unavailable.
    var cacheStatus: String = AppText.localized("正在统计缓存...", "Calculating cache...")
    /// The current document's index state, or "no PDF".
    var currentBookStatus: String = AppText.noPDF

    @ObservationIgnored var onBuildCurrentIndex: (() -> Void)?
    @ObservationIgnored var onTogglePaused: (() -> Void)?
    @ObservationIgnored var onCancelIndexing: (() -> Void)?
    @ObservationIgnored var onClearCurrentIndex: (() -> Void)?
    @ObservationIgnored var onClearCurrentWords: (() -> Void)?
    @ObservationIgnored var onClearAllCache: (() -> Void)?

    func refresh(cacheStatus: String? = nil, currentBookStatus: String? = nil) {
        if let cacheStatus { self.cacheStatus = cacheStatus }
        if let currentBookStatus { self.currentBookStatus = currentBookStatus }
    }

    // MARK: - Rows

    var currentBookActions: [SettingsAction] {
        [
            SettingsAction(
                id: CacheSettingsAccessibility.buildIndex,
                title: AppText.localized("生成/更新本书缓存", "Build / Update Book Cache"),
                symbol: "play.circle",
                tint: Color(red: 0.00, green: 0.48, blue: 1.00),
                perform: { [weak self] in self?.onBuildCurrentIndex?() }
            ),
            SettingsAction(
                id: CacheSettingsAccessibility.pauseIndex,
                title: AppText.localized("暂停/继续", "Pause / Resume"),
                symbol: "pause.circle",
                tint: Color(red: 1.00, green: 0.58, blue: 0.00),
                perform: { [weak self] in self?.onTogglePaused?() }
            ),
            SettingsAction(
                id: CacheSettingsAccessibility.cancelIndex,
                title: AppText.localized("取消分析", "Cancel"),
                symbol: "minus.circle",
                tint: Color(red: 1.00, green: 0.22, blue: 0.28),
                perform: { [weak self] in self?.onCancelIndexing?() }
            ),
            SettingsAction(
                id: CacheSettingsAccessibility.clearBookIndex,
                title: AppText.localized("清除本书分析缓存", "Clear Book Analysis Cache"),
                symbol: "paintbrush",
                role: .destructive,
                tint: Color(red: 0.60, green: 0.27, blue: 1.00),
                perform: { [weak self] in self?.onClearCurrentIndex?() }
            ),
            SettingsAction(
                id: CacheSettingsAccessibility.clearBookWords,
                title: AppText.localized("清除本书单词记录", "Clear Book Words"),
                symbol: "trash",
                role: .destructive,
                tint: Color(red: 0.00, green: 0.72, blue: 0.74),
                perform: { [weak self] in self?.onClearCurrentWords?() }
            )
        ]
    }

    var allCacheActions: [SettingsAction] {
        [
            SettingsAction(
                id: CacheSettingsAccessibility.clearAllCache,
                title: AppText.localized("清除全部缓存", "Clear All Cache"),
                symbol: "trash",
                role: .destructive,
                tint: Color(red: 1.00, green: 0.16, blue: 0.18),
                perform: { [weak self] in self?.onClearAllCache?() }
            )
        ]
    }
}
