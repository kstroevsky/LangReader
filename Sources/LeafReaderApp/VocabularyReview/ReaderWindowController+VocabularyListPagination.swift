import Cocoa

extension ReaderWindowController {
    /// Fills the list model from the current page of records. Replaces the old
    /// `populateVocabularyStack`, which tore down and rebuilt a stack of views.
    func populateVocabularyList(records: [VocabularyExportRecord], filter: VocabularyFilter) {
        let model = vocabularyPanelController.listModel
        let page = vocabularyReviewSession.currentListPageRecords(records, matching: filter)
        model.pageIndex = page.pageIndex
        model.pageCount = page.pageCount
        model.totalCount = page.total
        model.emptyMessage = page.total == 0 ? emptyVocabularyStateMessage(filter: filter) : nil
        model.rows = page.records.map(vocabularyWordRow(for:))
    }

    private func vocabularyWordRow(for record: VocabularyExportRecord) -> VocabularyWordRow {
        let theme = ReaderTheme.selected
        let word = record.word
        let hasAnswer = VocabularyExporter.hasTrimmedText(record.answer)
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        return VocabularyWordRow(
            id: key,
            word: word,
            location: record.location,
            status: hasAnswer
                ? vocabularySRSStatusText(record.srs)
                : AppText.localized("已保存在本地", "Saved locally"),
            hasPronunciation: vocabularySpeakerWord(word) != nil,
            answer: hasAnswer
                ? AttributedString(MarkdownRenderer.render(
                    String(vocabularyAnswerBody(record.answer, word: word).prefix(900)),
                    fontSize: 15,
                    textColor: vocabularyBodyTextColor(for: theme)
                  ))
                : nil,
            occurrences: record.occurrences.map { occurrence in
                let context = VocabularyExporter.hasTrimmedText(occurrence.context)
                    ? occurrence.context
                    : AppText.localized("没有可用的上下文", "No context available")
                return VocabularyWordRow.Occurrence(
                    id: occurrence.id,
                    location: occurrence.location,
                    context: AttributedString(vocabularyExampleAttributedString(
                        context,
                        word: occurrence.surfaceForm ?? word,
                        fontSize: 12,
                        textColor: vocabularyBodyTextColor(for: theme)
                    ))
                )
            },
            isExpanded: vocabularyState.expandedOccurrenceKeys.contains(key),
            formCount: record.forms.count,
            recordIDs: record.ids
        )
    }

    func handleVocabularyListAction(_ action: VocabularyWordListAction) {
        switch action {
        case .speak(let word): speakVocabularyTexts([word])
        case .copy(let word): copyTextToClipboard(word)
        case .delete(let ids): markVocabularyRecordsMastered(ids: ids)
        case .toggleOccurrences(let key): toggleVocabularyOccurrences(key: key)
        case .openOccurrence(let id): openVocabularyOccurrence(id: id)
        case .previousPage:
            if vocabularyReviewSession.goToPreviousListPage() { reloadVocabularyPanelContent() }
        case .nextPage:
            if vocabularyReviewSession.goToNextListPage() { reloadVocabularyPanelContent() }
        }
    }

    @objc func previousVocabularyListPage(_ sender: NSButton) {
        guard vocabularyReviewSession.goToPreviousListPage() else { return }
        reloadVocabularyPanelContent()
    }

    @objc func nextVocabularyListPage(_ sender: NSButton) {
        vocabularyReviewSession.goToNextListPage()
        reloadVocabularyPanelContent()
    }

    /// Why the list or the review has nothing to show. Shared by the AppKit
    /// list's empty view and the SwiftUI review card.
    func emptyVocabularyStateMessage(filter: VocabularyFilter) -> String {
        switch filter {
        case .due:
            return AppText.localized("今天还没有学习过的单词", "No words studied today")
        case .new:
            return AppText.localized("今天没有新加入的单词", "No new words added today")
        case .all:
            return AppText.localized("暂无单词", "No words yet")
        }
    }

    func emptyVocabularyState(filter: VocabularyFilter, isDark: Bool) -> NSView {
        let label = NSTextField(labelWithString: emptyVocabularyStateMessage(filter: filter))
        label.font = AppFont.semibold(ofSize: 15)
        label.textColor = ReaderTheme.selected.secondaryTextColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 120),
            label.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])
        return wrapper
    }
}
