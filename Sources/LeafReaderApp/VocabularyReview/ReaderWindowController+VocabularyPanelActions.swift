import Cocoa
import LeafReaderCore

extension ReaderWindowController {
    func reloadVocabularyPanelContent() {
        guard let panel = vocabularyPanelController.panel,
              let root = panel.contentView else { return }
        let filter = selectedVocabularyListFilter(in: root)
        let isDark = ReaderTheme.selected == .dark
        refreshVocabularyListContent(in: root, filter: filter)
        refreshVocabularyStats(in: root, records: currentVocabularyExportRecords)
        if !vocabularyReviewSession.listModeEnabled,
           let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) {
            populateVocabularyReviewContainer(reviewContainer, records: currentVocabularyExportRecords, filter: filter, isDark: isDark, autoPlayNewCard: !vocabularyReviewSession.listModeEnabled)
        }
    }

    func scheduleVocabularyPanelReload() {
        vocabularyPanelController.scheduleReload()
        vocabularyLibraryWindowController.scheduleReload()
    }

    func refreshVocabularyStats(in root: NSView, records: [VocabularyExportRecord]) {
        vocabularyPanelController.headerModel.apply(
            stats: VocabularyLearningStatsCalculator.stats(records: records)
        )
    }
}
