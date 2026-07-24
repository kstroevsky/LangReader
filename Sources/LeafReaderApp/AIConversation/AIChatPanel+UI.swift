import Cocoa
import SwiftUI

extension AIChatPanel {
    /// The panel is three stacked regions: a SwiftUI header, the AppKit
    /// transcript, and a SwiftUI status row above the AppKit input bar. The
    /// transcript and input bar stay AppKit because both carry
    /// selectable/editable text, which does not get first responder inside an
    /// `NSHostingView`; the chrome around them is declarative.
    func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = panelBackgroundColor.cgColor
        chromeModel.theme = readerTheme
        wireChromeModel()

        let header = chromeHostingView(AIPanelHeaderView(model: chromeModel))
        chromeHeaderView = header
        let status = chromeHostingView(AIPanelStatusView(model: chromeModel))

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        transcriptStack.orientation = .vertical
        transcriptStack.alignment = .leading
        transcriptStack.spacing = 10
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = transcriptStack

        inputBar.wantsLayer = true
        inputBar.layer?.backgroundColor = inputBackgroundColor.cgColor
        inputBar.layer?.cornerRadius = 8
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        inputField.placeholderString = AppText.followUpPlaceholder
        inputField.font = NSFont.systemFont(ofSize: Self.readerBodyFontSize)
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(sendFollowUp)
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputBar.focusField = inputField

        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendFollowUp)
        sendButton.contentTintColor = sendButtonTintColor
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
        for view in [header, scrollView, status, inputBar] as [NSView] {
            addSubview(view)
        }

        let inset = AIPanelChromeLayout.horizontalInset
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: AIPanelChromeLayout.headerHeight),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            scrollView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),

            transcriptStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            transcriptStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            transcriptStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            transcriptStack.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            transcriptStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            status.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),
            status.heightAnchor.constraint(equalToConstant: AIPanelChromeLayout.statusHeight),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            inputBar.heightAnchor.constraint(equalToConstant: 44),

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    /// A hosting view for one of the chrome regions. `safeAreaRegions = []` for
    /// the same reason the reader's bars need it: the panel reaches the window's
    /// top safe area, and without this the header would be pushed below the
    /// title-bar strip in a windowed window but not in full screen.
    private func chromeHostingView<Content: View>(_ view: Content) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.safeAreaRegions = []
        return hosting
    }

    private func wireChromeModel() {
        chromeModel.action = { [weak self] button in
            guard let self else { return }
            switch button {
            case .ask: self.startQuestion()
            case .summarize: self.summarizeCurrentContent()
            case .translate: self.translateCurrentContent()
            case .export: self.exportConversation()
            case .cancelRequest: self.cancelCurrentRequest()
            }
        }
    }

    func refreshLanguage() {
        inputField.placeholderString = AppText.followUpPlaceholder
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        chromeModel.languageToken &+= 1
        if !messages.isEmpty, messages[0].role == "system" {
            messages[0] = ChatMessage(role: "system", content: AIPromptStore.systemPrompt())
        }
    }
}
