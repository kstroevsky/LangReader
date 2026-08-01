import Cocoa
import SwiftUI
import LeafReaderCore

extension ReadingNotePanelController {
    func buildContent(in panel: NSPanel) {
        rootView.wantsLayer = true
        rootView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = rootView

        configureAIToolbar()
        configureAskInput()
        aiActionButtons.forEach {
            configureAIButton($0)
            aiToolbar.addArrangedSubview($0)
        }
        let scrollView = buildEditorScrollView()
        configureEditorTextView(in: scrollView)

        let editorChrome = NSHostingView(rootView: makeEditorChromeView(theme: ReaderTheme.selected))
        editorChrome.translatesAutoresizingMaskIntoConstraints = false
        editorChromeHostingView = editorChrome

        let editorStatus = NSHostingView(rootView: ReadingNoteEditorStatusView(model: editorModel, theme: ReaderTheme.selected))
        editorStatus.translatesAutoresizingMaskIntoConstraints = false
        editorStatusHostingView = editorStatus

        let editorWordCount = NSHostingView(rootView: ReadingNoteEditorWordCountView(model: editorModel, theme: ReaderTheme.selected))
        editorWordCount.translatesAutoresizingMaskIntoConstraints = false
        editorWordCountHostingView = editorWordCount

        editorContainer.wantsLayer = true
        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        let editorToolbar = buildEditorToolbar()
        editorContainer.addSubview(scrollView)
        editorContainer.addSubview(editorToolbar)
        editorContainer.addSubview(editorWordCount)

        rootView.addSubview(editorChrome)
        rootView.addSubview(editorContainer)
        rootView.addSubview(editorStatus)
        rootView.addSubview(aiToolbarContainer)
        rootView.addSubview(askInputContainer)
        NSLayoutConstraint.activate([
            editorChrome.topAnchor.constraint(equalTo: rootView.topAnchor),
            editorChrome.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            editorChrome.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            editorChrome.heightAnchor.constraint(equalToConstant: Metrics.chromeHeaderHeight),

            editorContainer.topAnchor.constraint(equalTo: editorChrome.bottomAnchor, constant: 10),
            editorContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Metrics.panelOuterMargin),
            editorContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Metrics.panelOuterMargin),
            editorContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -42),

            scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editorToolbar.topAnchor),
            editorToolbar.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorToolbar.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorToolbar.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
            editorToolbar.heightAnchor.constraint(equalToConstant: Metrics.editorToolbarHeight),
            editorStatus.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor, constant: 6),
            editorStatus.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: -6),
            editorStatus.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -9),
            editorStatus.heightAnchor.constraint(equalToConstant: 16),
            editorWordCount.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor, constant: -20),
            editorWordCount.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor),
            editorWordCount.widthAnchor.constraint(equalToConstant: 52),
            editorWordCount.heightAnchor.constraint(equalToConstant: 20)
        ])
        updateWordCount()
        DispatchQueue.main.async { [weak self] in
            self?.textView.scrollToBeginningOfDocument(nil)
        }
    }

    private func buildEditorScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        self.scrollView = scrollView
        return scrollView
    }

    private func buildEditorToolbar() -> NSStackView {
        let save = iconButton(symbol: "square.and.arrow.down", action: #selector(saveTapped(_:)))
        save.toolTip = AppText.localized("保存当前阅读笔记", "Save this reading note")
        let undo = iconButton(symbol: "arrow.uturn.backward", action: #selector(undoTapped(_:)))
        let redo = iconButton(symbol: "arrow.uturn.forward", action: #selector(redoTapped(_:)))
        let bold = textButton(title: "B", action: #selector(boldTapped(_:)))
        let italic = textButton(title: "I", action: #selector(italicTapped(_:)))
        italic.font = NSFontManager.shared.convert(AppFont.semibold(ofSize: 16), toHaveTrait: .italicFontMask)
        let list = iconButton(symbol: "list.bullet", action: #selector(listTapped(_:)))
        let check = iconButton(symbol: "checklist", action: #selector(checklistTapped(_:)))
        let template = iconButton(symbol: "doc.plaintext", action: #selector(templateTapped(_:)))
        template.toolTip = AppText.localized("插入阅读笔记模板", "Insert reading note template")
        let image = iconButton(symbol: "photo", action: #selector(imageTapped(_:)))
        let buttons = [save, undo, redo, toolbarSeparator(), bold, italic, list, check, template, image]
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 86)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func toolbarSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func configureAIToolbar() {
        aiToolbarContainer.isHidden = true
        aiToolbarContainer.wantsLayer = true
        aiToolbarContainer.layer?.cornerRadius = 9
        aiToolbarContainer.layer?.shadowOpacity = 0.16
        aiToolbarContainer.layer?.shadowRadius = 12
        aiToolbarContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        aiToolbarContainer.frame = NSRect(x: 0, y: 0, width: 360, height: 38)

        aiToolbar.orientation = .horizontal
        aiToolbar.alignment = .centerY
        aiToolbar.distribution = .fillEqually
        aiToolbar.spacing = 4
        aiToolbar.edgeInsets = NSEdgeInsets(top: 4, left: 5, bottom: 4, right: 5)
        aiToolbar.translatesAutoresizingMaskIntoConstraints = false
        aiToolbarContainer.addSubview(aiToolbar)
        NSLayoutConstraint.activate([
            aiToolbar.topAnchor.constraint(equalTo: aiToolbarContainer.topAnchor),
            aiToolbar.leadingAnchor.constraint(equalTo: aiToolbarContainer.leadingAnchor),
            aiToolbar.trailingAnchor.constraint(equalTo: aiToolbarContainer.trailingAnchor),
            aiToolbar.bottomAnchor.constraint(equalTo: aiToolbarContainer.bottomAnchor)
        ])
    }

    private func configureAskInput() {
        setAskInputVisible(false)
        askInputContainer.wantsLayer = true
        askInputContainer.layer?.cornerRadius = 9
        askInputContainer.layer?.shadowOpacity = 0.16
        askInputContainer.layer?.shadowRadius = 12
        askInputContainer.layer?.shadowOffset = NSSize(width: 0, height: -2)
        askInputContainer.frame = NSRect(x: 0, y: 0, width: 340, height: 42)

        askInputField.placeholderString = AppText.localized("输入问题", "Ask about the selection")
        askInputField.font = NSFont.systemFont(ofSize: 14)
        askInputField.isBordered = false
        askInputField.drawsBackground = false
        askInputField.focusRingType = .none
        askInputField.target = self
        askInputField.action = #selector(submitAskQuestion(_:))
        askInputField.translatesAutoresizingMaskIntoConstraints = false

        askSendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        askSendButton.isBordered = false
        askSendButton.target = self
        askSendButton.action = #selector(submitAskQuestion(_:))
        askSendButton.translatesAutoresizingMaskIntoConstraints = false

        askInputContainer.addSubview(askInputField)
        askInputContainer.addSubview(askSendButton)
        NSLayoutConstraint.activate([
            askInputField.leadingAnchor.constraint(equalTo: askInputContainer.leadingAnchor, constant: 12),
            askInputField.trailingAnchor.constraint(equalTo: askSendButton.leadingAnchor, constant: -8),
            askInputField.centerYAnchor.constraint(equalTo: askInputContainer.centerYAnchor),
            askSendButton.trailingAnchor.constraint(equalTo: askInputContainer.trailingAnchor, constant: -10),
            askSendButton.centerYAnchor.constraint(equalTo: askInputContainer.centerYAnchor),
            askSendButton.widthAnchor.constraint(equalToConstant: 26),
            askSendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func configureAIButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.font = AppFont.semibold(ofSize: 13)
        button.target = self
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 52).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        switch button {
        case explainButton:
            button.action = #selector(explainSelection(_:))
        case translateButton:
            button.action = #selector(translateSelection(_:))
        case summarizeButton:
            button.action = #selector(summarizeSelection(_:))
        case polishButton:
            button.action = #selector(polishSelection(_:))
        case difficultSentenceButton:
            button.action = #selector(analyzeDifficultSentence(_:))
        case askButton:
            button.action = #selector(showAskInput(_:))
        default:
            break
        }
    }

    private func iconButton(symbol: String, action: Selector, pointSize: CGFloat = 15) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        let button = ReadingNoteIconButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func textButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }
}
