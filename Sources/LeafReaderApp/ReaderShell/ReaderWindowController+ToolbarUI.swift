import Cocoa

extension ReaderWindowController {
    func configureToolbarViews() -> ReaderToolbarSetup {
        let toolbar = readerBarView()
        let zoomOut = plainButton(title: "-", action: #selector(ReaderWindowController.zoomOut))
        let zoomIn = plainButton(title: "+", action: #selector(ReaderWindowController.zoomIn))
        let leftDivider = divider()
        let rightDivider = divider()
        let zoomGroup = NSView()

        toolbarView = toolbar
        configureTitleControls()
        configureReadAloudControl()
        configureZoomControls(zoomGroup: zoomGroup, zoomOut: zoomOut, zoomIn: zoomIn, leftDivider: leftDivider, rightDivider: rightDivider)
        configurePageAndSearchControls()
        configureTopRightControls()
        configureRelatedFormsToggle()

        // Clusters are built from `ReaderToolbarLayout.items`, so the arrays
        // there are the toolbar's composition. A stack also collapses hidden
        // controls automatically, which is what makes `ReaderChromeState`
        // visibility reflow correctly instead of leaving a hole.
        let leadingStack = toolbarCluster(.leading, spacing: ReaderToolbarLayout.titleClusterSpacing)
        let beforeZoomStack = toolbarCluster(.beforeZoom, spacing: ReaderToolbarLayout.clusterSpacing)
        let trailingStack = toolbarCluster(.trailing, spacing: ReaderToolbarLayout.clusterSpacing)

        // The centered cluster stays individually positioned: it is anchored to
        // the window centre rather than flowing from an edge.
        for view in [zoomGroup, pageLabel, searchUnderlineButton!, searchButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }
        for stack in [leadingStack, beforeZoomStack, trailingStack] {
            toolbar.addSubview(stack)
        }

        return ReaderToolbarSetup(
            toolbar: toolbar,
            zoomOut: zoomOut,
            zoomIn: zoomIn,
            leftDivider: leftDivider,
            rightDivider: rightDivider,
            zoomGroup: zoomGroup,
            leadingStack: leadingStack,
            beforeZoomStack: beforeZoomStack,
            trailingStack: trailingStack
        )
    }

    /// Builds one toolbar cluster from its descriptors.
    private func toolbarCluster(
        _ placement: ReaderToolbarItem.Placement,
        spacing: CGFloat
    ) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .horizontal)

        for item in ReaderToolbarLayout.items(in: placement) {
            guard let view = toolbarView(for: item.id) else { continue }
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            if let width = item.width {
                view.widthAnchor.constraint(equalToConstant: width).isActive = true
            }
            if item.id != .title {
                // Only the title may compress; every other control keeps its size.
                view.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            if let height = toolbarItemHeight(for: item.id) {
                view.heightAnchor.constraint(equalToConstant: height).isActive = true
            }
        }
        return stack
    }

    /// The view that renders a descriptor.
    private func toolbarView(for id: ReaderToolbarItem.Identifier) -> NSView? {
        switch id {
        case .cover: return coverImageView
        case .title: return titleLabel
        case .relatedFormsToggle: return relatedFormsToggle
        case .readAloud: return readAloudButton
        case .readAloudStop: return readAloudStopButton
        case .pageLayout: return pageLayoutButton
        case .crop: return cropButton
        case .fullScreen: return fullScreenButton
        }
    }

    private func toolbarItemHeight(for id: ReaderToolbarItem.Identifier) -> CGFloat? {
        switch id {
        case .cover: return ReaderUILayout.coverSize.height
        case .title: return nil
        default: return ReaderUILayout.toolbarButtonHeight
        }
    }

    func configureBottomBarViews() -> ReaderBottomBarSetup {
        let bottomBar = readerBarView()
        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openAISettings))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: AppText.settings)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        settingsButton.setAccessibilityIdentifier(ReaderBottomBarItem.Identifier.settings.accessibilityIdentifier)
        let navigationStack = NSStackView()

        bottomBarView = bottomBar
        // Built from `ReaderBottomBarLayout`, so the bar's contents and order
        // are the array rather than the order of these statements.
        for item in ReaderBottomBarLayout.items where item.id != .settings {
            let button = capsuleButton(
                title: bottomBarTitle(for: item.id),
                symbol: bottomBarSymbol(for: item.id),
                action: bottomBarAction(for: item.id),
                showsLeadingSymbol: item.showsLeadingSymbol
            )
            button.toolTip = bottomBarTooltip(for: item.id)
            // A stable, locale-independent handle for the smoke test and
            // assistive tech. Distinct from `.identifier`, which the capsule
            // buttons already use to mark themselves for theming.
            button.setAccessibilityIdentifier(item.id.accessibilityIdentifier)
            assign(button, to: item.id)
        }

        embeddingStatusLabel.font = AppFont.semibold(ofSize: 12)
        embeddingStatusLabel.alignment = .right
        embeddingStatusLabel.lineBreakMode = .byTruncatingMiddle
        embeddingStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        embeddingStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateEmbeddingStatusTextColor()
        embeddingStatusLabel.isHidden = true
        embeddingPauseButton.isHidden = true
        embeddingCancelButton.isHidden = true

        navigationStack.orientation = .horizontal
        navigationStack.alignment = .centerY
        navigationStack.distribution = .fill
        navigationStack.spacing = ReaderUILayout.navigationStackSpacing
        for button in [tocButton!, coverButton!, prevButton!, nextButton!, farthestPositionButton!] {
            button.translatesAutoresizingMaskIntoConstraints = false
            navigationStack.addArrangedSubview(button)
        }

        for view in [settingsButton, recentButton!, vocabularyLibraryButton!, notesButton!, vocabularyButton!, navigationStack, embeddingStatusLabel, embeddingPauseButton!, embeddingCancelButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(view)
        }

        return ReaderBottomBarSetup(bottomBar: bottomBar, settingsButton: settingsButton, navigationStack: navigationStack)
    }


    // MARK: Bottom bar descriptors -> real buttons

    /// The selector each descriptor drives. Kept here rather than in
    /// `ReaderBottomBarItem` so the descriptor stays free of AppKit.
    private func bottomBarAction(for id: ReaderBottomBarItem.Identifier) -> Selector {
        switch id {
        case .settings: return #selector(openAISettings)
        case .shelf: return #selector(showRecentDocuments)
        case .words: return #selector(showVocabularyLibrary)
        case .notes: return #selector(showReadingNotesPanel(_:))
        case .review: return #selector(showVocabularyBook)
        case .toc: return #selector(showTableOfContents)
        case .cover: return #selector(goToCover)
        case .previousPage: return #selector(prevPage)
        case .nextPage: return #selector(nextPage)
        case .farthestPosition: return #selector(goToFarthestReadingPosition)
        case .embeddingPause: return #selector(toggleEmbeddingBackfillPaused)
        case .embeddingCancel: return #selector(cancelEmbeddingBackfill)
        }
    }

    private func bottomBarTitle(for id: ReaderBottomBarItem.Identifier) -> String {
        switch id {
        case .settings: return ""
        case .shelf: return AppText.localized("书架", "Shelf")
        case .words: return AppText.localized("生词", "Words")
        case .notes: return AppText.localized("笔记", "Notes")
        case .review: return AppText.localized("背单词", "Review")
        case .toc: return AppText.localized("目录", "TOC")
        case .cover: return AppText.cover
        case .previousPage: return AppText.prev
        case .nextPage: return AppText.next
        case .farthestPosition: return AppText.localized("上次位置", "Last")
        case .embeddingPause: return AppText.localized("暂停", "Pause")
        case .embeddingCancel: return AppText.localized("取消", "Cancel")
        }
    }

    private func bottomBarSymbol(for id: ReaderBottomBarItem.Identifier) -> String {
        switch id {
        case .settings: return "gearshape"
        case .shelf: return "books.vertical"
        case .words: return "text.word.spacing"
        case .notes: return "note.text"
        case .review: return "text.book.closed"
        case .toc: return "list.bullet"
        case .cover: return "book.closed"
        case .previousPage: return "chevron.left"
        case .nextPage: return "chevron.right"
        case .farthestPosition: return "arrow.turn.down.right"
        case .embeddingPause: return "pause.fill"
        case .embeddingCancel: return "xmark"
        }
    }

    private func bottomBarTooltip(for id: ReaderBottomBarItem.Identifier) -> String? {
        switch id {
        case .words: return AppText.localized("打开所有文档中的生词", "Open saved words from all documents")
        case .review: return AppText.localized("复习当前文档中的单词", "Review words from the current document")
        case .farthestPosition: return AppText.localized("跳到本书阅读过的最远位置", "Jump to the farthest read position in this book")
        case .embeddingPause: return AppText.localized("暂停/继续 AI 分析", "Pause/resume AI analysis")
        case .embeddingCancel: return AppText.localized("取消本次 AI 分析任务", "Cancel this AI analysis task")
        default: return nil
        }
    }

    /// The controller keeps a named reference to each button for visibility and
    /// theming; this is the one place the descriptor meets those properties.
    private func assign(_ button: NSButton, to id: ReaderBottomBarItem.Identifier) {
        switch id {
        case .settings: break
        case .shelf: recentButton = button
        case .words: vocabularyLibraryButton = button
        case .notes: notesButton = button
        case .review: vocabularyButton = button
        case .toc: tocButton = button
        case .cover: coverButton = button
        case .previousPage: prevButton = button
        case .nextPage: nextButton = button
        case .farthestPosition: farthestPositionButton = button
        case .embeddingPause: embeddingPauseButton = button
        case .embeddingCancel: embeddingCancelButton = button
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
        coverImageView.isHidden = true
    }

    func configureZoomControls(zoomGroup: NSView, zoomOut: NSButton, zoomIn: NSButton, leftDivider: NSView, rightDivider: NSView) {
        zoomGroupView = zoomGroup
        zoomGroup.wantsLayer = true
        zoomGroup.layer?.backgroundColor = controlBackgroundColor(for: ReaderTheme.selected).cgColor
        zoomGroup.layer?.borderColor = controlBorderColor(for: ReaderTheme.selected).cgColor
        zoomGroup.layer?.borderWidth = 1
        zoomGroup.layer?.cornerRadius = 7

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
    }

    func configureReadAloudControl() {
        readAloudButton = capsuleButton(
            title: AppText.localized("朗读", "Read"),
            symbol: "speaker.wave.2",
            action: #selector(toggleReadAloudFromToolbar),
            showsLeadingSymbol: true
        )
        readAloudButton.toolTip = AppText.localized("从当前屏幕顶部开始朗读", "Read from the top of the current screen")
        readAloudStopButton = capsuleButton(
            title: AppText.localized("停止", "Stop"),
            symbol: "stop.fill",
            action: #selector(stopReadAloudFromToolbarAction),
            showsLeadingSymbol: true
        )
        readAloudStopButton.toolTip = AppText.localized("停止朗读", "Stop reading")
        readAloudStopButton.isHidden = true
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

    func configureTopRightControls() {
        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        pageLayoutButton = capsuleButton(title: "", symbol: "rectangle.split.2x1", action: #selector(togglePDFPageLayout))
        pageLayoutButton.toolTip = AppText.localized("切换单页/双页浏览", "Toggle single/two-page view")
        cropButton = capsuleButton(title: "", symbol: "crop", action: #selector(togglePDFMarginCrop))
        cropButton.toolTip = AppText.localized("裁掉 PDF 页面外侧空白", "Crop outer PDF margins")
        updatePDFPageLayoutButton()
        updatePDFMarginCropButton()
    }

    func configureRelatedFormsToggle() {
        let container = NSView()
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        icon.contentTintColor = ReaderTheme.selected.secondaryTextColor
        icon.imageScaling = .scaleProportionallyDown

        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.state = showsRelatedWordForms ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleRelatedWordForms(_:))
        // The cluster stack hugs its content at required priority, so both parts
        // pin their intrinsic width rather than risk being compressed by it.
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let tip = AppText.localized("显示相关词形的蓝色标注", "Show blue markings for related word forms")
        toggle.toolTip = tip
        icon.toolTip = tip
        container.toolTip = tip

        for view in [icon, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            toggle.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggle.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            toggle.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])

        relatedFormsToggle = container
        relatedFormsSwitch = toggle
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
