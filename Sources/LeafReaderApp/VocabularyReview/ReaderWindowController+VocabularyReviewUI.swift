import Cocoa
import SwiftUI
import LeafReaderCore

extension ReaderWindowController {
    func populateVocabularyReviewContainer(_ container: NSView, records: [VocabularyExportRecord], filter: VocabularyFilter, isDark: Bool, autoPlayNewCard: Bool = true) {
        container.subviews.forEach { $0.removeFromSuperview() }

        let model = VocabularyReviewCardModel()
        guard let selection = VocabularyReviewCardSelector.selection(records: records, session: vocabularyReviewSession) else {
            model.emptyMessage = emptyVocabularyStateMessage(filter: filter)
            hostVocabularyReviewCard(model, in: container)
            return
        }

        let displayRecord = vocabularyRecordWithDictionaryMetadata(selection.record)
        prepareVocabularyReviewTiming(for: displayRecord, autoPlay: autoPlayNewCard)
        updateVocabularySummaryWithProgress(position: selection.position, total: selection.total)

        configureVocabularyReviewCardModel(model, record: displayRecord)
        hostVocabularyReviewCard(model, in: container)
    }

    /// Fills the card model from a record and the session's phase.
    private func configureVocabularyReviewCardModel(
        _ model: VocabularyReviewCardModel,
        record: VocabularyExportRecord
    ) {
        let session = vocabularyReviewSession
        let theme = ReaderTheme.selected

        model.word = record.word
        model.tags = VocabularyTagFormatter.displayText(for: record.dictionaryTags)
        model.hasPronunciation = vocabularySpeakerWord(record.word) != nil
        model.phase = session.answerShown ? .answer : (session.contextShown ? .context : .prompt)
        model.didScore = session.didScoreCurrentCard
        model.canUndo = !session.undoSRSByID.isEmpty

        // Rich text stays with the existing AppKit renderers and is bridged, as
        // the Words detail pane already does — markdown is not re-implemented.
        model.makeContext = { [weak self] in
            guard let self else { return NSAttributedString() }
            let contextText = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaningful = self.isMeaningfulVocabularyContext(contextText)
                ? contextText
                : AppText.localized("没有可用的原文句子。", "No source sentence available.")
            return self.vocabularyExampleAttributedString(
                meaningful,
                word: record.word,
                fontSize: 19,
                textColor: self.vocabularyBodyTextColor(for: theme)
            )
        }
        model.makeAnswer = { [weak self] in
            guard let self else { return NSAttributedString() }
            let contextText = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaningful = self.isMeaningfulVocabularyContext(contextText) ? contextText : ""
            let body = [
                meaningful.isEmpty ? "" : AppText.localized("原文上下文：\(meaningful)", "Context: \(meaningful)"),
                self.vocabularyAnswerBody(record.answer, word: record.word)
            ].filter { !$0.isEmpty }.joined(separator: "\n\n")
            let rendered = MarkdownRenderer.render(
                body,
                fontSize: 16,
                textColor: self.vocabularyBodyTextColor(for: theme)
            )
            return self.emphasizedVocabularyWord(in: rendered, word: record.word, boldFontSize: 16)
        }
        model.action = { [weak self] action in
            self?.handleVocabularyReviewAction(action, word: record.word)
        }
    }

    private func handleVocabularyReviewAction(_ action: VocabularyReviewAction, word: String) {
        switch action {
        case .know: rememberedVocabularyCard()
        case .doNotKnow: showVocabularyContext()
        case .rememberedAfterContext: rememberedAfterContextVocabularyCard()
        case .forgot: showVocabularyAnswer()
        case .next: nextVocabularyReviewCard()
        case .undo: undoVocabularyReviewScore()
        case .speak: speakVocabularyTexts([word])
        }
    }

    private func hostVocabularyReviewCard(_ model: VocabularyReviewCardModel, in container: NSView) {
        let hosting = NSHostingView(rootView: VocabularyReviewCardView(model: model, theme: ReaderTheme.selected))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // The card fills the region the panel gives it. Without lowering these,
        // the hosting view demands its SwiftUI ideal height and grows the whole
        // panel — the AppKit card could not, because its content area was boxed
        // in between a header and a fixed-height footer.
        hosting.setContentHuggingPriority(.defaultLow, for: .vertical)
        hosting.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        hosting.setAccessibilityIdentifier(VocabularyReviewAccessibility.card)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    func vocabularyReviewPriorityPopup() -> NSPopUpButton {
        let popup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = AppFont.semibold(ofSize: 13)
        popup.isBordered = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItem(withTitle: AppText.localized("老单词优先", "Old Words First"))
        popup.lastItem?.representedObject = VocabularyReviewPriority.oldWordsFirst.rawValue
        popup.addItem(withTitle: AppText.localized("新单词优先", "New Words First"))
        popup.lastItem?.representedObject = VocabularyReviewPriority.newWordsFirst.rawValue
        popup.addItem(withTitle: AppText.localized("词频优先", "Frequency First"))
        popup.lastItem?.representedObject = VocabularyReviewPriority.frequencyFirst.rawValue
        popup.menu?.autoenablesItems = false
        popup.target = self
        popup.action = #selector(changeVocabularyReviewPriority(_:))
        popup.theme = ReaderTheme.selected
        loadVocabularyReviewPreferences()
        if let index = popup.itemArray.firstIndex(where: { item in
            (item.representedObject as? String) == vocabularyReviewSession.priority.rawValue
        }) {
            popup.selectItem(at: index)
        }
        return popup
    }

    @objc func changeVocabularyReviewPriority(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let priority = VocabularyReviewPriority(rawValue: rawValue),
              priority != vocabularyReviewSession.priority,
              let root = vocabularyPanelController.rootView else { return }
        commitPendingVocabularyAnswerIfNeeded()
        vocabularyReviewSession.priority = priority
        saveVocabularyReviewPriorityPreference(priority)
        vocabularyReviewSession.resetForReviewMode()
        if priority == .frequencyFirst {
            backfillFrequencyForCurrentTrainerIfNeeded(autoPlayAfterCompletion: true)
            return
        }
        showVocabularyReviewMode(in: root, autoPlay: true)
    }

    func vocabularyDailyGoalPopup() -> NSPopUpButton {
        let popup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = AppFont.semibold(ofSize: 13)
        popup.isBordered = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        for goal in VocabularyDailyGoalPolicy.options {
            popup.addItem(withTitle: AppText.localized("目标 \(goal)", "Goal \(goal)"))
            popup.lastItem?.representedObject = goal
        }
        popup.menu?.autoenablesItems = false
        popup.target = self
        popup.action = #selector(changeVocabularyDailyGoal(_:))
        popup.theme = ReaderTheme.selected
        loadVocabularyReviewPreferences()
        if let index = popup.itemArray.firstIndex(where: { ($0.representedObject as? Int) == vocabularyReviewSession.dailyReviewGoal }) {
            popup.selectItem(at: index)
        }
        return popup
    }

    @objc func changeVocabularyDailyGoal(_ sender: NSPopUpButton) {
        guard let goal = sender.selectedItem?.representedObject as? Int,
              vocabularyPanelController.rootView != nil else { return }
        vocabularyReviewSession.dailyReviewGoal = goal
        saveVocabularyDailyGoalPreference(goal)
        vocabularyPanelController.headerModel.summary = vocabularySummaryText(
            records: currentVocabularyExportRecords,
            filter: vocabularyReviewSession.filter
        )
    }

    func showVocabularyFrequencyLoading(in root: NSView) {
        guard let reviewContainer = findView(identifier: "vocabularyReviewContainer", in: root) else { return }
        for view in reviewContainer.subviews {
            view.removeFromSuperview()
        }
        let label = NSTextField(labelWithString: AppText.localized("正在处理词频，请稍候…", "Processing word frequency..."))
        label.font = AppFont.semibold(ofSize: 16)
        label.textColor = vocabularySecondaryTextColor(for: ReaderTheme.selected)
        label.alignment = .center
        label.identifier = NSUserInterfaceItemIdentifier("vocabularyFrequencyLoadingLabel")
        label.translatesAutoresizingMaskIntoConstraints = false
        reviewContainer.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: reviewContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: reviewContainer.centerYAnchor)
        ])
    }

    func updateVocabularyFrequencyLoading(in root: NSView, word: String, current: Int, total: Int) {
        guard let label = findView(identifier: "vocabularyFrequencyLoadingLabel", in: root) as? NSTextField else { return }
        label.stringValue = AppText.localized(
            "正在处理词频 \(current) / \(total)：\(word)",
            "Processing frequency \(current) / \(total): \(word)"
        )
    }

    func vocabularyExampleAttributedString(_ text: String, word: String, fontSize: CGFloat, textColor: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 8
        let attributed = NSAttributedString(
                string: text,
                attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )
        return emphasizedVocabularyWord(in: attributed, word: word, boldFontSize: fontSize)
    }

    func emphasizedVocabularyWord(in attributed: NSAttributedString, word: String, boldFontSize: CGFloat) -> NSAttributedString {
        let target = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let pattern = vocabularyWordEmphasisPattern(for: target)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return attributed
        }
        let fullRange = NSRange(location: 0, length: (mutable.string as NSString).length)
        regex.enumerateMatches(in: mutable.string, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound, range.length > 0 else { return }
            mutable.addAttribute(.font, value: AppFont.semibold(ofSize: boldFontSize + 1), range: range)
        }
        return mutable
    }

    func vocabularyWordEmphasisPattern(for word: String) -> String {
        VocabularyTextPolicy.emphasisPattern(for: word)
    }

}
