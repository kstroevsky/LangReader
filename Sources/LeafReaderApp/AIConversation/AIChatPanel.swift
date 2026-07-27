import AVFoundation
import Cocoa
import LeafReaderCore

final class ChatInputTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            copySelectionToClipboard()
            return true
        case "x":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            copySelectionToClipboard()
            currentEditor()?.delete(nil)
            return true
        case "v":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            pasteFromClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    func copySelectionToClipboard() {
        currentEditor()?.copySelectionToClipboard()
    }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.pasteStringFromClipboard(transform: normalizedSingleLinePasteText)
        } else {
            stringValue += normalizedSingleLinePasteText(text)
        }
    }

    private func normalizedSingleLinePasteText(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

final class ChatInputBarView: NSView {
    weak var focusField: NSTextField?

    override func mouseDown(with event: NSEvent) {
        if let focusField {
            window?.makeFirstResponder(focusField)
            return
        }
        super.mouseDown(with: event)
    }
}

final class ChatBubbleTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        (delegate as? AIChatPanel)?.beginBubbleTextSelection(self)
        super.mouseDown(with: event)
        (delegate as? AIChatPanel)?.finishBubbleTextSelection(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)),
              event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return super.performKeyEquivalent(with: event)
        }
        return copySelectionToClipboard() || super.performKeyEquivalent(with: event)
    }

    func copySelectionToClipboard() -> Bool {
        currentEditor()?.copySelectionToClipboard() ?? false
    }

    func clearTextSelection() {
        currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        window?.makeFirstResponder(nil)
    }

    var selectedTextValue: String {
        guard let editor = currentEditor() else { return "" }
        return editor.selectedString()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var selectedTextRange: NSRange? {
        guard let editor = currentEditor() else { return nil }
        let range = editor.selectedRange
        return range.length > 0 ? range : nil
    }
}

final class WordSpeakerButton: NSButton {
    var spokenWord: String?

    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class BubbleDeleteButton: NSButton {
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class AIChatPanel: NSView, NSTextFieldDelegate {
    static let readerBodyFontSize: CGFloat = 15
    static let bubbleBodyFontSize: CGFloat = 17
    static let maxSavedConversationBubbles = 100
    static let maxContextMessages = 40
    static let maxVisibleNormalConversationBubbles = 120
    static let maxInitialLinkedWordBubbles = 30
    static let maxInitialSavedConversationBubbles = 40

    let client = AIClient()
    let dictionaryLookupService: DictionaryLookupService = LocalDictionaryLookupService.shared
    lazy var llmAnswerProvider: StreamingAnswerProvider = LLMAnswerProvider(client: client)
    /// State behind the SwiftUI header and status row.
    let chromeModel = AIPanelChromeModel()
    /// The header's hosting view, kept so the selection monitor can tell a click
    /// on the header's actions from a click that should clear the selection.
    weak var chromeHeaderView: NSView?
    let scrollView = NSScrollView()
    let transcriptStack = FlippedStackView()
    // The transcript and the follow-up field stay AppKit: both are
    // selectable/editable text, which does not receive first responder inside
    // an NSHostingView. Only the chrome above and below them is SwiftUI.
    let inputBar = ChatInputBarView()
    let inputField = ChatInputTextField(string: "")
    let sendButton = NSButton(title: "", target: nil, action: nil)
    let speechSynthesizer = AVSpeechSynthesizer()
    let requestState = AIRequestState()
    var lastFailedAIRequest: FailedAIRequest?

    var onAskSelectedText: ((String) -> String?)?
    var onSelectedWordQuestionStarted: ((WordQuestionRequest) -> WordQuestionStartResult?)?
    var onLinkedWordAnswerAvailable: ((String) -> String?)?
    var onLinkedAnswerCompleted: ((String, String, String) -> Void)?
    var onLinkedAnswerFailed: ((String) -> Void)?
    var onLinkedBubbleSelected: ((String) -> Void)?
    var onLinkedBubbleDeleted: ((String) -> Void)?
    /// Opens the Words window focused on the given word (the Occurrences button).
    var onOccurrencesRequested: ((String) -> Void)?
    /// Grammatical summary (POS, forms, occurrence count) for the focused word.
    var onWordFocusInfoRequested: ((String) -> WordFocusInfo?)?
    var onSummarizeCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onTranslateCurrentContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onCurrentReadingContent: ((@escaping ((title: String, text: String)?) -> Void) -> Void)?
    var onDocumentQuestionPrompt: DocumentQuestionPromptHandler?
    var onDocumentQuestionCancelled: (() -> Void)?
    var onSettingsRequired: (() -> Void)?
    var onConversationChanged: ((SavedAIConversation) -> Void)?
    var onConversationBubblesDeleted: (([SavedAIConversationBubble]) -> Void)?
    var onConversationSourcesChanged: (([AIConversationSourceLocation]) -> Void)?
    var onCurrentSourceLocation: (() -> AIConversationSourceLocation?)?
    var onConversationBubbleSelected: ((AIConversationSourceLocation) -> Void)?
    var onNonFollowUpSelectionInteraction: (() -> Void)?
    var lastNotifiedConversationSources: [AIConversationSourceLocation] = []

    var selectedText = ""
    lazy var conversationContext = AIConversationContextStore(
        maxContextMessages: Self.maxContextMessages,
        systemPromptProvider: AIPromptStore.systemPrompt
    )
    var transcriptEntries: [TranscriptEntry] {
        get { conversationContext.transcriptEntries }
        set { conversationContext.replaceTranscriptEntries(newValue) }
    }
    var messages: [ChatMessage] {
        get { conversationContext.messages }
        set { conversationContext.replaceMessages(newValue) }
    }
    /// Forwarded rather than stored: the chrome model owns it, so the panel's
    /// guards and the animated dots cannot disagree. They were two properties
    /// written together by `setBusy`, which was correct only for as long as that
    /// stayed the single writer.
    var isBusy: Bool {
        get { chromeModel.isBusy }
        set { chromeModel.isBusy = newValue }
    }
    var pendingStreamText = ""
    var lastStreamUpdateAt = Date.distantPast
    var isEditingFollowUp = false
    var ignoreEmptySelectionUntil = Date.distantPast
    var localMouseMonitor: Any?
    weak var activeBubbleTextField: ChatBubbleTextField?
    var activeBubbleSelectionRange: NSRange?
    var activeBubbleSelectedText = ""
    var streamUpdateWorkItem: DispatchWorkItem?
    var transcriptLayoutWorkItem: DispatchWorkItem?
    weak var pendingTranscriptScrollTarget: NSView?
    var pendingTranscriptForceScroll = false
    var readerTheme: ReaderTheme = .original
    var isDarkMode = false
    /// The transcript's data: ordering, metadata and persistence all live here,
    /// not in the stack view's arranged subviews.
    let transcript = AITranscriptModel()
    /// View lookup only — which box is showing a given linked word.
    var bubbleBoxByLinkID: [String: ChatBubbleView] = [:]
    var isLoadingLinkedWordBubbles = false
    var isRestoringSavedConversation = false
    var selectedLinkID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        installInteractionMonitor()
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        streamUpdateWorkItem?.cancel()
        transcriptLayoutWorkItem?.cancel()
        requestState.cancelTasks()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContentVisible(_ visible: Bool) {
        subviews.forEach { $0.isHidden = !visible }
        layer?.backgroundColor = visible
            ? panelBackgroundColor.cgColor
            : NSColor.clear.cgColor
        needsLayout = true
    }

    func setDarkMode(_ enabled: Bool) {
        setTheme(enabled ? .dark : .original)
    }

    func setTheme(_ theme: ReaderTheme) {
        readerTheme = theme
        isDarkMode = theme == .dark
        chromeModel.theme = theme
        layer?.backgroundColor = panelBackgroundColor.cgColor
        inputBar.layer?.backgroundColor = inputBackgroundColor.cgColor
        inputBar.layer?.borderWidth = theme == .original ? 0 : 1
        inputBar.layer?.borderColor = inputBorderColor.cgColor
        inputField.textColor = primaryTextColor
        sendButton.contentTintColor = sendButtonTintColor
        restyleTranscript()
    }
}
