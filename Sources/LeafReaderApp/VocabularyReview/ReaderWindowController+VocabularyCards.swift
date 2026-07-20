import Cocoa

extension ReaderWindowController {
    func vocabularyCard(record: VocabularyExportRecord, isDark: Bool) -> NSView {
        _ = isDark
        let theme = ReaderTheme.selected
        let word = record.word
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = vocabularyCardBackgroundColor(for: theme).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = vocabularyCardBorderColor(for: theme).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let bullet = NSTextField(labelWithString: "•")
        bullet.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        bullet.textColor = vocabularyAccentColor(for: theme)
        bullet.alignment = .center
        bullet.translatesAutoresizingMaskIntoConstraints = false

        let wordLabel = NSTextField(labelWithString: word)
        wordLabel.font = AppFont.semibold(ofSize: 19)
        wordLabel.textColor = vocabularyPrimaryTextColor(for: theme)
        wordLabel.lineBreakMode = .byTruncatingTail
        wordLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false

        let speakerButton: VocabularySpeakerButton? = vocabularySpeakerWord(word).map { spokenWord in
            let button = VocabularySpeakerButton(title: "", target: self, action: #selector(playVocabularyWord(_:)))
            button.image = TemplateSymbolImage.make("speaker.wave.2.fill", accessibilityDescription: AppText.localized("播放发音", "Play pronunciation"))
            button.isBordered = false
            button.contentTintColor = vocabularyAccentColor(for: theme)
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.spokenWord = spokenWord
            button.toolTip = AppText.localized("播放单词发音", "Play word pronunciation")
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }

        let copyButton = vocabularyActionButton(
            title: AppText.localized("复制", "Copy"),
            target: self,
            action: #selector(copyVocabularyWordFromList(_:)),
            fontSize: 13
        )
        copyButton.identifier = NSUserInterfaceItemIdentifier(word)
        copyButton.controlSize = .small
        copyButton.widthAnchor.constraint(equalToConstant: 68).isActive = true

        let locationLabel = NSTextField(labelWithString: record.location)
        locationLabel.font = AppFont.semibold(ofSize: 14)
        locationLabel.textColor = vocabularySecondaryTextColor(for: theme)
        locationLabel.alignment = .right
        locationLabel.lineBreakMode = .byTruncatingTail
        locationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let hasAnswer = VocabularyExporter.hasTrimmedText(record.answer)
        let statusLabel = NSTextField(labelWithString: hasAnswer
            ? vocabularySRSStatusText(record.srs)
            : AppText.localized("已保存在本地", "Saved locally"))
        statusLabel.font = AppFont.semibold(ofSize: 14)
        statusLabel.textColor = vocabularySecondaryTextColor(for: theme)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let masteredButton = vocabularyActionButton(title: AppText.localized("删除", "Delete"), target: self, action: #selector(markVocabularyRecordMastered(_:)), fontSize: 14)
        masteredButton.controlSize = .small
        masteredButton.identifier = NSUserInterfaceItemIdentifier(record.ids.joined(separator: "|"))

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addArrangedSubview(wordLabel)
        if let speakerButton {
            header.addArrangedSubview(speakerButton)
            speakerButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
            speakerButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        header.addArrangedSubview(copyButton)
        header.addArrangedSubview(locationLabel)

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 12
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addArrangedSubview(statusLabel)
        statusRow.addArrangedSubview(masteredButton)
        masteredButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        masteredButton.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(statusRow)

        if hasAnswer {
            let answerBody = vocabularyAnswerBody(record.answer, word: word)
            let answerLabel = NSTextField(
                labelWithAttributedString: MarkdownRenderer.render(
                    String(answerBody.prefix(900)),
                    fontSize: 15,
                    textColor: vocabularyBodyTextColor(for: theme)
                )
            )
            answerLabel.maximumNumberOfLines = 0
            answerLabel.lineBreakMode = .byWordWrapping
            answerLabel.isSelectable = true
            answerLabel.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(answerLabel)
            answerLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        if !record.occurrences.isEmpty {
            let groupKey = VocabularyTextPolicy.canonicalVocabularyKey(word)
            let isExpanded = vocabularyState.expandedOccurrenceKeys.contains(groupKey)
            let labeledForms = record.forms.compactMap { form -> String? in
                guard let label = form.label, label.isInformative else { return nil }
                return "\(form.surface) \(label.displayName)"
            }
            let formPrefix: String
            if !labeledForms.isEmpty {
                formPrefix = labeledForms.joined(separator: " · ") + " · "
            } else if record.forms.count > 1 {
                formPrefix = AppText.localized(
                    "词形（\(record.forms.count)） · ",
                    "Forms (\(record.forms.count)) · "
                )
            } else {
                formPrefix = ""
            }
            let disclosure = vocabularyActionButton(
                title: AppText.localized(
                    "\(formPrefix)出现位置（\(record.occurrences.count)）\(isExpanded ? " ▲" : " ▼")",
                    "\(formPrefix)Occurrences (\(record.occurrences.count)) \(isExpanded ? "▲" : "▼")"
                ),
                target: self,
                action: #selector(toggleVocabularyOccurrences(_:)),
                fontSize: 13
            )
            disclosure.identifier = NSUserInterfaceItemIdentifier(groupKey)
            disclosure.heightAnchor.constraint(equalToConstant: 28).isActive = true
            contentStack.addArrangedSubview(disclosure)

            if isExpanded {
                let occurrenceStack = NSStackView()
                occurrenceStack.orientation = .vertical
                occurrenceStack.alignment = .width
                occurrenceStack.spacing = 6
                occurrenceStack.translatesAutoresizingMaskIntoConstraints = false
                record.occurrences
                    .map { vocabularyOccurrenceRow($0, word: word, theme: theme) }
                    .forEach(occurrenceStack.addArrangedSubview)
                contentStack.addArrangedSubview(occurrenceStack)
                occurrenceStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            }
        }

        card.addSubview(bullet)
        card.addSubview(contentStack)

        NSLayoutConstraint.activate([
            bullet.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
            bullet.centerXAnchor.constraint(equalTo: card.leadingAnchor, constant: 46),
            bullet.widthAnchor.constraint(equalToConstant: 18),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 74),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
        return card
    }

    private func vocabularyOccurrenceRow(_ occurrence: VocabularyOccurrence, word: String, theme: ReaderTheme) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 7
        row.layer?.backgroundColor = vocabularyPanelBackgroundColor(for: theme).withAlphaComponent(0.55).cgColor
        row.translatesAutoresizingMaskIntoConstraints = false

        let pageButton = vocabularyActionButton(
            title: occurrence.location,
            target: self,
            action: #selector(openVocabularyOccurrence(_:)),
            fontSize: 12
        )
        pageButton.identifier = NSUserInterfaceItemIdentifier(occurrence.id)
        pageButton.controlSize = .small

        let context = VocabularyExporter.hasTrimmedText(occurrence.context)
            ? occurrence.context
            : AppText.localized("没有可用的上下文", "No context available")
        let contextLabel = NSTextField(wrappingLabelWithString: context)
        contextLabel.attributedStringValue = vocabularyExampleAttributedString(
            context,
            word: occurrence.surfaceForm ?? word,
            fontSize: 12,
            textColor: vocabularyBodyTextColor(for: theme)
        )
        contextLabel.maximumNumberOfLines = 3
        contextLabel.lineBreakMode = .byWordWrapping
        contextLabel.allowsEditingTextAttributes = true
        contextLabel.isSelectable = true
        contextLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(pageButton)
        row.addSubview(contextLabel)
        NSLayoutConstraint.activate([
            pageButton.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            pageButton.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            pageButton.widthAnchor.constraint(equalToConstant: 82),
            pageButton.heightAnchor.constraint(equalToConstant: 26),
            contextLabel.leadingAnchor.constraint(equalTo: pageButton.trailingAnchor, constant: 10),
            contextLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            contextLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            contextLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
        return row
    }

    @objc func copyVocabularyWordFromList(_ sender: NSButton) {
        guard let word = sender.identifier?.rawValue, !word.isEmpty else { return }
        copyTextToClipboard(word)
    }

    @objc func toggleVocabularyOccurrences(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, !key.isEmpty else { return }
        if vocabularyState.expandedOccurrenceKeys.contains(key) {
            vocabularyState.expandedOccurrenceKeys.remove(key)
        } else {
            vocabularyState.expandedOccurrenceKeys.insert(key)
        }
        scheduleVocabularyPanelReload()
    }

    @objc func openVocabularyOccurrence(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, !id.isEmpty else { return }
        closeVocabularyPanel()
        DispatchQueue.main.async { [weak self] in
            self?.jumpToStoredLinkedWord(linkID: id)
        }
    }

    func vocabularySRSStatusText(_ srs: VocabularySRSState) -> String {
        let ef = String(format: "%.2f", srs.easeFactor)
        if srs.isMastered {
            return AppText.localized("已掌握 · 连续主动想起 \(srs.activeRecallStreak ?? 0) 次 · EF \(ef)", "Mastered · active recall streak \(srs.activeRecallStreak ?? 0) · EF \(ef)")
        }
        if srs.lapseCount >= 2 {
            return AppText.localized("吃力词 · 已查看答案 \(srs.lapseCount) 次 · EF \(ef)", "Hard word · answer checked \(srs.lapseCount)x · EF \(ef)")
        }
        if srs.isNew {
            return AppText.localized("新词 · 今天开始学习 · EF \(ef)", "New · start today · EF \(ef)")
        }
        if srs.isDue {
            return AppText.localized("今天复习 · 连续 \(srs.repetition) 次 · EF \(ef)", "Due today · streak \(srs.repetition) · EF \(ef)")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = srs.intervalDays == 0 ? .short : .none
        return AppText.localized(
            srs.intervalDays == 0 ? "下次：\(formatter.string(from: srs.dueDate)) · 短间隔重测 · EF \(ef)" : "下次：\(formatter.string(from: srs.dueDate)) · 间隔 \(srs.intervalDays) 天 · EF \(ef)",
            srs.intervalDays == 0 ? "Next: \(formatter.string(from: srs.dueDate)) · short retry · EF \(ef)" : "Next: \(formatter.string(from: srs.dueDate)) · \(srs.intervalDays)d · EF \(ef)"
        )
    }

    func isMeaningfulVocabularyContext(_ context: String) -> Bool {
        let contextText = VocabularyExporter.trimmed(context)
        guard contextText.count >= 3 else { return false }
        return contextText.range(of: #"[\p{L}\p{N}]"#, options: .regularExpression) != nil
    }
}
