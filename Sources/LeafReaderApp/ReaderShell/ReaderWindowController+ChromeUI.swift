import Cocoa

extension ReaderWindowController {
    /// The one place chrome visibility is applied. Callers describe the reader's
    /// situation with a `ReaderChromeState`; nothing else may set `isHidden` on
    /// these controls, so a new control is wired here once instead of at every
    /// load path.
    func applyChromeState(_ state: ReaderChromeState) {
        chromeState = state
        topBarModel.showsCover = state.showsCover
        topBarModel.showsPageLayoutButton = state.showsPageLayoutButton
        topBarModel.showsCropButton = state.showsCropButton
        topBarModel.showsRelatedFormsToggle = state.showsRelatedFormsToggle
        topBarModel.showsReadAloudStopButton = state.showsReadAloudStopButton
        if state.showsRelatedFormsToggle {
            topBarModel.relatedFormsOn = state.relatedFormsToggleIsOn
        }
    }

    /// Recomputes the chrome for the document now on screen. Used by the load
    /// paths and by anything that changes a condition the chrome depends on.
    func refreshChromeState(presentation: ReaderChromeState.Presentation? = nil) {
        let resolved = presentation ?? chromeState.presentation
        applyChromeState(
            .make(
                presentation: resolved,
                isReadAloudActive: isReadAloudActive,
                showsRelatedWordForms: showsRelatedWordForms,
                hasCoverImage: coverImageView.image != nil
            )
        )
    }

    func configureLoadingOverlay() {
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.isHidden = true
        loadingOverlay.wantsLayer = true
        loadingOverlay.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.86).cgColor

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .regular
        loadingIndicator.isDisplayedWhenStopped = false

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.font = AppFont.semibold(ofSize: 13)
        loadingLabel.textColor = NSColor(red: 0.32, green: 0.36, blue: 0.44, alpha: 1)
        loadingLabel.alignment = .center
        loadingLabel.lineBreakMode = .byTruncatingMiddle

        loadingOverlay.addSubview(loadingIndicator)
        loadingOverlay.addSubview(loadingLabel)
    }

    func iconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        setSystemImage(symbol, on: button)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = ReaderTheme.selected.primaryTextColor
        return button
    }

    func plainButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 18)
        return button
    }

    func setSystemImage(_ symbol: String, on button: NSButton, accessibilityDescription: String? = nil) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)
        if button.image == nil, button.title.isEmpty {
            button.title = accessibilityDescription ?? ""
        }
    }

    func divider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = toolbarBorderColor(for: ReaderTheme.selected).cgColor
        return view
    }

    func refreshLanguageUI() {
        (NSApp.delegate as? AppDelegate)?.refreshMainMenu()
        bottomBarModel.languageToken += 1
        topBarModel.languageToken += 1
        aiPanel.refreshLanguage()
        // The top and bottom bars are SwiftUI and re-render from the language
        // tokens above; the stateful button titles refresh via their updaters.
        selectionActionToolbar.refreshLanguage()
        selectionActionToolbar.applyTheme(ReaderTheme.selected)
        refreshEmbeddingStatusLanguage()
        updatePDFPageLayoutButton()
        updatePDFMarginCropButton()
        updateFullScreenButton()
        if pdfView.document == nil {
            pageLabel.stringValue = AppText.noPDF
            updatePageLabelTextColor()
        }
    }
}
