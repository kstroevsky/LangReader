import Cocoa

extension AIChatPanel {
    /// Clears the transcript back to an empty state, resetting every tracking
    /// structure that references the removed bubbles.
    ///
    /// Shared by the focused-word view and the (now empty) linked-word load, so
    /// there is one definition of "what a clean transcript means".
    func resetTranscript() {
        transcriptStack.arrangedSubviews.forEach { view in
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bubbleMetadataByID.removeAll()
        bubbleBoxByLinkID.removeAll()
        persistentBubbleIDs.removeAll()
        lastNotifiedConversationSources.removeAll()
        selectedLinkID = nil
        conversationContext.reset()
    }

    /// Shows a single word: a grammatical header (part of speech, forms, an
    /// Occurrences button) followed by its definition, replacing whatever the
    /// transcript held. This is what "Define" and clicking a saved word both
    /// produce, so the Assistant reads as a focused dictionary rather than a
    /// running list of every word.
    func showFocusedWord(word: String, answer: String, linkID: String?) {
        isRestoringSavedConversation = true
        defer { isRestoringSavedConversation = false }

        resetTranscript()

        let info = onWordFocusInfoRequested?(word)
        let header = makeWordFocusHeaderView(word: word, info: info)
        transcriptStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appendBubble(role: AppText.aiRole, text: trimmed, collapsible: false, renderMarkdown: true, linkID: linkID)
            recordTranscript(role: AppText.aiRole, text: trimmed, linkID: linkID)
            appendMessage(ChatMessage(role: "assistant", content: trimmed, linkID: linkID))
        }
        scheduleTranscriptLayout()
    }

    private func makeWordFocusHeaderView(word: String, info: WordFocusInfo?) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let wordLabel = NSTextField(labelWithString: word)
        wordLabel.font = AppFont.semibold(ofSize: 22)
        wordLabel.textColor = primaryTextColor
        wordLabel.lineBreakMode = .byTruncatingTail

        // The occurrence count lives in the button now, so the meta line carries
        // only the part of speech.
        var metaParts: [String] = []
        if let pos = info?.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines), !pos.isEmpty {
            metaParts.append(pos)
        }
        let metaLabel = NSTextField(labelWithString: metaParts.joined(separator: "  ·  "))
        metaLabel.font = AppFont.semibold(ofSize: 12)
        metaLabel.textColor = secondaryTextColor
        metaLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(wordLabel)
        if !metaParts.isEmpty {
            stack.addArrangedSubview(metaLabel)
        }
        if let formsText = info?.formsText?.trimmingCharacters(in: .whitespacesAndNewlines), !formsText.isEmpty {
            let formsLabel = NSTextField(labelWithString: AppText.localized("词形：\(formsText)", "Forms: \(formsText)"))
            formsLabel.font = NSFont.systemFont(ofSize: 12)
            formsLabel.textColor = secondaryTextColor
            formsLabel.maximumNumberOfLines = 0
            formsLabel.lineBreakMode = .byWordWrapping
            formsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(formsLabel)
        }

        let count = info?.occurrenceCount ?? 0
        let occurrencesTitle = count > 0
            ? AppText.localized("出处（\(count)）", "Occurrences (\(count))")
            : AppText.localized("出处", "Occurrences")
        let occurrencesButton = CapsuleChromeButton(
            title: occurrencesTitle,
            target: self,
            action: #selector(occurrencesButtonTapped(_:))
        )
        occurrencesButton.controlSize = .large
        occurrencesButton.font = AppFont.semibold(ofSize: 14)
        occurrencesButton.theme = readerTheme
        occurrencesButton.isDark = isDarkMode
        occurrencesButton.identifier = NSUserInterfaceItemIdentifier(word)
        occurrencesButton.translatesAutoresizingMaskIntoConstraints = false
        occurrencesButton.setContentHuggingPriority(.required, for: .horizontal)
        occurrencesButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        card.addSubview(stack)
        card.addSubview(occurrencesButton)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: occurrencesButton.leadingAnchor, constant: -12),
            occurrencesButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            occurrencesButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            occurrencesButton.heightAnchor.constraint(equalToConstant: 38)
        ])
        return card
    }

    @objc private func occurrencesButtonTapped(_ sender: NSButton) {
        guard let word = sender.identifier?.rawValue, !word.isEmpty else { return }
        onOccurrencesRequested?(word)
    }
}
