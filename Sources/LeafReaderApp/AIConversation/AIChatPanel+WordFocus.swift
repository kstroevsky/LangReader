import Cocoa
import LeafReaderCore

/// A read-only, selectable text view that sizes its own height to its content.
///
/// The focused word card renders every piece of text through this instead of an
/// `NSTextField`: a selectable text field swaps its static cell for the window's
/// field editor on click, which lays the text out with different padding and so
/// visibly shifts it. An `NSTextView` is the text system itself — there is no
/// cell/field-editor duality — so the text stays put while remaining selectable.
final class FocusCardTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let layoutManager = layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: container)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: ceil(layoutManager.usedRect(for: container).height)
        )
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}

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
        transcript.removeAll()
        bubbleBoxByLinkID.removeAll()
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

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript.focusedWord = FocusedWord(word: word, answer: trimmed, linkID: linkID)
        buildFocusedWordViews(word: word, answer: trimmed)

        if !trimmed.isEmpty {
            // Keep the follow-up context even though the card is not a chat bubble.
            recordTranscript(role: AppText.aiRole, text: trimmed, linkID: linkID)
            appendMessage(ChatMessage(role: "assistant", content: trimmed, linkID: linkID))
        }

        scheduleTranscriptLayout()
    }

    /// Rebuilds the focused-word card for the current theme. The card bakes its
    /// colours in when it is built and holds no chat bubbles, so the in-place
    /// restyling `restyleTranscript` does for bubbles never reached it — it
    /// stayed on the old theme until the next lookup. Rebuilding from the stored
    /// `focusedWord` is what fixes that.
    ///
    /// Returns false when the transcript is a conversation rather than a
    /// focused word, so the caller falls through to the bubble path.
    @discardableResult
    func restyleFocusedWordCard() -> Bool {
        guard transcript.focusedWord != nil else { return false }
        refreshFocusedWordCard()
        return true
    }

    func refreshFocusedWordCard() {
        guard let focused = transcript.focusedWord else { return }
        transcriptStack.arrangedSubviews.forEach { view in
            transcriptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buildFocusedWordViews(word: focused.word, answer: focused.answer)
        transcriptStack.needsLayout = true
        scheduleTranscriptLayout()
    }

    /// The card itself: header, definition, and the spacer that pins them to the
    /// top. Kept separate from `showFocusedWord` so a restyle can rebuild the
    /// views without re-recording the conversation context.
    private func buildFocusedWordViews(word: String, answer: String) {
        let info = onWordFocusInfoRequested?(word)
        let header = makeWordFocusHeaderView(word: word, info: info)
        transcriptStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true

        if !answer.isEmpty {
            let definition = makeWordFocusDefinitionView(answer: answer)
            transcriptStack.addArrangedSubview(definition)
            definition.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
        }

        // The transcript is a chat that grows from the bottom, so a short focused
        // card would otherwise sink to the bottom of the pane. A low-priority
        // spacer absorbs the slack and keeps the card pinned to the top.
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        transcriptStack.addArrangedSubview(spacer)
        spacer.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
    }

    private func makeWordFocusHeaderView(word: String, info: WordFocusInfo?) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false

        // Word + part of speech + forms are one selectable block; paragraph
        // spacing gives them the visual separation the old stacked labels had.
        let header = NSMutableAttributedString()
        let wordStyle = NSMutableParagraphStyle()
        wordStyle.paragraphSpacing = 6
        header.append(NSAttributedString(string: word, attributes: [
            .font: AppFont.semibold(ofSize: 22),
            .foregroundColor: primaryTextColor,
            .paragraphStyle: wordStyle
        ]))
        if let pos = info?.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines), !pos.isEmpty {
            let posStyle = NSMutableParagraphStyle()
            posStyle.paragraphSpacing = 2
            header.append(NSAttributedString(string: "\n" + pos, attributes: [
                .font: AppFont.semibold(ofSize: 12),
                .foregroundColor: secondaryTextColor,
                .paragraphStyle: posStyle
            ]))
        }
        if let formsText = info?.formsText?.trimmingCharacters(in: .whitespacesAndNewlines), !formsText.isEmpty {
            header.append(NSAttributedString(
                string: "\n" + AppText.localized("词形：\(formsText)", "Forms: \(formsText)"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: secondaryTextColor
                ]
            ))
        }
        let headerText = makeFocusCardTextView(header)

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

        let isSaved = info?.isSaved == true
        let saveButton = CapsuleChromeButton(
            title: isSaved
                ? AppText.localized("移除", "Remove")
                : AppText.localized("保存", "Save"),
            target: self,
            action: #selector(focusedWordSaveButtonTapped(_:))
        )
        saveButton.controlSize = .large
        saveButton.font = AppFont.semibold(ofSize: 14)
        saveButton.theme = readerTheme
        saveButton.isDark = isDarkMode
        saveButton.identifier = NSUserInterfaceItemIdentifier(word)
        saveButton.toolTip = isSaved
            ? AppText.localized("从当前文档中移除此单词", "Remove this word from the current document")
            : AppText.localized("将此单词保存到当前文档的词汇中", "Save this word in the current document")
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.setContentHuggingPriority(.required, for: .horizontal)
        saveButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        focusedWordSaveButton = saveButton

        card.addSubview(headerText)
        card.addSubview(saveButton)
        card.addSubview(occurrencesButton)
        NSLayoutConstraint.activate([
            headerText.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            headerText.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            headerText.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            headerText.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -12),
            saveButton.trailingAnchor.constraint(equalTo: occurrencesButton.leadingAnchor, constant: -8),
            saveButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            saveButton.heightAnchor.constraint(equalToConstant: 38),
            occurrencesButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            occurrencesButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            occurrencesButton.heightAnchor.constraint(equalToConstant: 38)
        ])
        return card
    }

    private func makeWordFocusDefinitionView(answer: String) -> NSView {
        let box = ChatBubbleView()
        box.fillColor = bubbleFillColor(role: AppText.aiRole)
        box.borderColor = bubbleBorderColor
        box.cornerRadius = 8
        box.translatesAutoresizingMaskIntoConstraints = false

        let textView = makeFocusCardTextView(
            bubbleString(role: AppText.aiRole, text: answer, renderMarkdown: true)
        )

        let copyButton = NSButton(title: "", target: self, action: #selector(copyFocusedDefinition(_:)))
        copyButton.isBordered = false
        copyButton.bezelStyle = .regularSquare
        copyButton.image = TemplateSymbolImage.make("doc.on.doc", accessibilityDescription: AppText.localized("复制", "Copy"))
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = secondaryTextColor
        copyButton.identifier = NSUserInterfaceItemIdentifier(answer)
        copyButton.toolTip = AppText.localized("复制", "Copy")
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(textView)
        box.addSubview(copyButton)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            textView.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            textView.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            textView.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
            copyButton.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            copyButton.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 20),
            copyButton.heightAnchor.constraint(equalToConstant: 20)
        ])
        return box
    }

    private func makeFocusCardTextView(_ attributed: NSAttributedString) -> FocusCardTextView {
        let textView = FocusCardTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textStorage?.setAttributedString(attributed)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    @objc private func occurrencesButtonTapped(_ sender: NSButton) {
        guard let word = sender.identifier?.rawValue, !word.isEmpty else { return }
        onOccurrencesRequested?(word)
    }

    @objc private func focusedWordSaveButtonTapped(_ sender: NSButton) {
        guard let focused = transcript.focusedWord,
              sender.identifier?.rawValue == focused.word else { return }
        onFocusedWordSaveToggleRequested?(focused.word, focused.answer)
        refreshFocusedWordCard()
    }

    @objc private func copyFocusedDefinition(_ sender: NSButton) {
        guard let text = sender.identifier?.rawValue, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
