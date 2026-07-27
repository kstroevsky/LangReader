import Cocoa
import SwiftUI
import LeafReaderCore

extension ReaderWindowController {
    func configureToolbarViews() -> ReaderToolbarSetup {
        let toolbar = readerBarView()
        toolbarView = toolbar
        topBarModel.theme = ReaderTheme.selected
        configureTitleControls()
        let zoomGroup = configureZoomControls()
        configurePageAndSearchControls()
        wireTopBarModel()

        let hosting = NSHostingView(rootView: ReaderTopBarView(
            model: topBarModel,
            title: titleLabel,
            cover: coverImageView
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Ignore the window's safe area. In a windowed window the top safe area
        // is the title-bar strip, and without this the hosting view centres its
        // controls *below* it — leaving the SwiftUI buttons ~17 px lower than the
        // AppKit zoom/page/search controls (which centre in the true toolbar).
        // Fullscreen has no title bar, which is why only windowed drifted.
        hosting.safeAreaRegions = []
        // A findable container so the smoke test can reach the nested SwiftUI
        // buttons without walking the reader's huge PDF accessibility tree.
        toolbar.setAccessibilityIdentifier(ReaderTopBarView.accessibilityIdentifier)
        toolbar.addSubview(hosting)

        // The centre cluster — the editable zoom group, editable page field and
        // search controls — stays AppKit and is layered on top of the hosting
        // view. Editable NSTextFields do not receive first responder for editing
        // inside an NSHostingView, so they cannot be bridged. Positioned by the
        // constraints in `installReaderLayoutConstraints`.
        for view in [zoomGroup, pageLabel, searchUnderlineButton, searchButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }

        // Seed the stateful native buttons from current state.
        updatePDFPageLayoutButton()
        updatePDFMarginCropButton()
        updateFullScreenButton()

        return ReaderToolbarSetup(toolbar: toolbar, hosting: hosting)
    }

    private func wireTopBarModel() {
        topBarModel.action = { [weak self] button in
            guard let self else { return }
            switch button {
            case .readAloud: self.toggleReadAloudFromToolbar()
            case .readAloudStop: self.stopReadAloudFromToolbarAction()
            case .pageLayout: self.togglePDFPageLayout()
            case .crop: self.togglePDFMarginCrop()
            case .fullScreen: self.toggleFullScreen()
            }
        }
        topBarModel.onRelatedFormsChanged = { [weak self] on in
            guard let self else { return }
            self.showsRelatedWordForms = on
            self.restoreStoredWordAnnotations()
        }
    }

    func configureBottomBarViews() -> ReaderBottomBarSetup {
        let bottomBar = readerBarView()
        bottomBarView = bottomBar
        bottomBarModel.theme = ReaderTheme.selected
        wireBottomBarModel()
        let hosting = NSHostingView(rootView: ReaderBottomBarView(model: bottomBarModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Same safe-area guard as the top bar (see there): centre in the true
        // bar bounds, not inside any window safe-area inset.
        hosting.safeAreaRegions = []
        // A findable container so the smoke test can reach the nested SwiftUI
        // buttons without walking the reader's huge PDF accessibility tree.
        bottomBar.setAccessibilityIdentifier("readerBottomBar")
        bottomBar.addSubview(hosting)
        return ReaderBottomBarSetup(bottomBar: bottomBar, hosting: hosting)
    }

    private func wireBottomBarModel() {
        bottomBarModel.action = { [weak self] id in
            guard let self else { return }
            switch id {
            case .settings: self.openAISettings()
            case .shelf: self.showRecentDocuments()
            case .words: self.showVocabularyLibrary()
            case .notes: self.showReadingNotesPanel(nil)
            case .review: self.showVocabularyBook()
            case .toc: self.showTableOfContents()
            case .cover: self.goToCover()
            case .previousPage: self.prevPage()
            case .nextPage: self.nextPage()
            case .farthestPosition: self.goToFarthestReadingPosition()
            case .embeddingPause: self.toggleEmbeddingBackfillPaused()
            case .embeddingCancel: self.cancelEmbeddingBackfill()
            }
        }
    }

    func configureTitleControls() {
        titleLabel.font = AppFont.semibold(ofSize: 15)
        titleLabel.textColor = ReaderTheme.selected.primaryTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.backgroundColor = controlBackgroundColor(for: ReaderTheme.selected).cgColor
        coverImageView.layer?.borderColor = controlBorderColor(for: ReaderTheme.selected).cgColor
        coverImageView.layer?.borderWidth = 1
        coverImageView.layer?.cornerRadius = 3
        coverImageView.layer?.masksToBounds = true
        // Presence in the toolbar is governed by the SwiftUI `if model.showsCover`
        // now, not by `isHidden`, so the bridged view must stay unhidden.
        coverImageView.isHidden = false
    }

    @discardableResult
    func configureZoomControls() -> NSView {
        let zoomGroup = NSView()
        zoomGroupView = zoomGroup
        zoomGroup.translatesAutoresizingMaskIntoConstraints = false
        zoomGroup.wantsLayer = true
        zoomGroup.layer?.backgroundColor = controlBackgroundColor(for: ReaderTheme.selected).cgColor
        zoomGroup.layer?.borderColor = controlBorderColor(for: ReaderTheme.selected).cgColor
        zoomGroup.layer?.borderWidth = 1
        zoomGroup.layer?.cornerRadius = 7

        let zoomOut = plainButton(title: "-", action: #selector(ReaderWindowController.zoomOut))
        let zoomIn = plainButton(title: "+", action: #selector(ReaderWindowController.zoomIn))
        let leftDivider = divider()
        let rightDivider = divider()

        zoomField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        zoomField.alignment = .center
        zoomField.isBordered = false
        zoomField.drawsBackground = false
        zoomField.focusRingType = .none
        zoomField.isEditable = true
        zoomField.isSelectable = true
        zoomField.delegate = self
        zoomField.target = self
        zoomField.action = #selector(applyZoomFromField)

        for view in [zoomOut, leftDivider, zoomField, rightDivider, zoomIn] {
            view.translatesAutoresizingMaskIntoConstraints = false
            zoomGroup.addSubview(view)
        }

        // The zoom group is now self-contained — its own size plus its internal
        // layout — so it bridges into the SwiftUI toolbar as one unit, keeping
        // the editable field's delegate wiring and the ± buttons intact.
        NSLayoutConstraint.activate([
            zoomGroup.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.width),
            zoomGroup.heightAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.height),

            zoomOut.leadingAnchor.constraint(equalTo: zoomGroup.leadingAnchor),
            zoomOut.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomOut.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomOut.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomButtonWidth),
            leftDivider.leadingAnchor.constraint(equalTo: zoomOut.trailingAnchor),
            leftDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            leftDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            leftDivider.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomDividerWidth),
            zoomField.leadingAnchor.constraint(equalTo: leftDivider.trailingAnchor),
            zoomField.centerYAnchor.constraint(equalTo: zoomGroup.centerYAnchor),
            zoomField.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomFieldWidth),
            rightDivider.leadingAnchor.constraint(equalTo: zoomField.trailingAnchor),
            rightDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            rightDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomDividerWidth),
            zoomIn.leadingAnchor.constraint(equalTo: rightDivider.trailingAnchor),
            zoomIn.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomIn.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: zoomGroup.trailingAnchor)
        ])
        return zoomGroup
    }

    func configurePageAndSearchControls() {
        pageLabel.font = AppFont.semibold(ofSize: 15)
        pageLabel.alignment = .center
        pageLabel.isBordered = false
        pageLabel.drawsBackground = false
        pageLabel.focusRingType = .none
        pageLabel.isEditable = true
        pageLabel.isSelectable = true
        pageLabel.delegate = self
        pageLabel.target = self
        pageLabel.action = #selector(applyPageFromField)
        pageLabel.toolTip = AppText.localized("输入页码后按回车跳转", "Enter a page number and press Return")
        updatePageLabelTextColor()

        searchUnderlineButton = SearchUnderlineButton(title: "", target: self, action: #selector(showSearchOverlay))
        searchUnderlineButton.toolTip = AppText.localized("搜索文档", "Search document")
        searchUnderlineButton.theme = ReaderTheme.selected
        searchButton = iconButton(symbol: "magnifyingglass", action: #selector(showSearchOverlay))
        searchButton.toolTip = AppText.localized("搜索文档", "Search document")
    }

    func readerBarView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = toolbarBackgroundColor(for: ReaderTheme.selected).cgColor
        view.layer?.borderColor = toolbarBorderColor(for: ReaderTheme.selected).cgColor
        view.layer?.borderWidth = 1
        return view
    }
}
