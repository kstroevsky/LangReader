import Cocoa
import LeafReaderCore

extension ReaderWindowController {
    @objc func changeVocabularyTab(_ sender: NSSegmentedControl) {
        changeVocabularyTab(index: sender.selectedSegment)
    }

    func changeVocabularyTab(index selectedSegment: Int) {
        guard let panel = vocabularyPanelController.panel,
              let root = panel.contentView else { return }
        commitPendingVocabularyAnswerIfNeeded()
        if selectedSegment == 0 {
            vocabularyReviewSession.resetForReviewMode()
            showVocabularyReviewMode(in: root, autoPlay: true)
            return
        }
        let filter = vocabularyFilter(forSegment: selectedSegment)
        vocabularyReviewSession.resetForListMode(filter: filter)
        refreshVocabularyListContent(in: root, filter: filter)
        showVocabularyListMode(in: root)
    }

    func showVocabularyReviewMode(in root: NSView, autoPlay: Bool) {
        findView(identifier: "vocabularyReviewContainer", in: root)?.isHidden = false
        findView(identifier: "vocabularyList", in: root)?.isHidden = true
        findView(identifier: "vocabularyReviewPriorityPopup", in: root)?.isHidden = false
        findView(identifier: "vocabularyReviewGoalPopup", in: root)?.isHidden = false
        findView(identifier: "vocabularyExportMarkdownButton", in: root)?.isHidden = true
        findView(identifier: "vocabularyExportCSVButton", in: root)?.isHidden = true
        if let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) {
            let isDark = ReaderTheme.selected == .dark
            populateVocabularyReviewContainer(reviewContainer, records: currentVocabularyExportRecords, filter: vocabularyReviewSession.filter, isDark: isDark, autoPlayNewCard: autoPlay)
        }
    }

    func showVocabularyListMode(in root: NSView) {
        vocabularyReviewSession.listModeEnabled = true
        findView(identifier: "vocabularyReviewContainer", in: root)?.isHidden = true
        findView(identifier: "vocabularyList", in: root)?.isHidden = false
        findView(identifier: "vocabularyReviewPriorityPopup", in: root)?.isHidden = true
        findView(identifier: "vocabularyReviewGoalPopup", in: root)?.isHidden = true
        findView(identifier: "vocabularyExportMarkdownButton", in: root)?.isHidden = false
        findView(identifier: "vocabularyExportCSVButton", in: root)?.isHidden = false
    }

    func refreshVocabularyListContent(in root: NSView, filter: VocabularyFilter) {
        populateVocabularyList(records: currentVocabularyExportRecords, filter: filter)
        vocabularyPanelController.headerModel.summary = vocabularySummaryText(
            records: currentVocabularyExportRecords,
            filter: filter
        )
    }

    func vocabularyFilter(forSegment selectedSegment: Int) -> VocabularyFilter {
        switch selectedSegment {
        case 1:
            return .due
        case 2:
            return .new
        case 3:
            return .all
        default:
            return vocabularyReviewSession.filter
        }
    }

    func selectedVocabularyListFilter(in root: NSView?) -> VocabularyFilter {
        vocabularyReviewSession.filter
    }

}
