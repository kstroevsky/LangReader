import Cocoa

extension AISettingsPanelController {
    func show(attachedTo window: NSWindow, initialTab: SettingsTab = .general) {
        parentWindow = window
        let settingsFontSize: CGFloat = 14
        let theme = ReaderTheme.selected
        let isDark = theme == .dark
        let panelBackground: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        switch theme {
        case .original:
            panelBackground = .white
            primaryText = NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
            secondaryText = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        case .eyeCare:
            panelBackground = NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
            primaryText = NSColor(red: 0.15, green: 0.13, blue: 0.09, alpha: 1)
            secondaryText = NSColor(red: 0.45, green: 0.39, blue: 0.27, alpha: 1)
        case .dark:
            panelBackground = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            primaryText = NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            secondaryText = NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
        let formBackground = settingsFormBackgroundColor(for: theme)
        let layout = AISettingsLayoutMetrics()

        let panel = makeSettingsPanel(isDark: isDark)
        let content = makeSettingsContentView(panel: panel, isDark: isDark, backgroundColor: panelBackground)

        let titleIcon = settingsTitleIcon(primaryText: primaryText)
        let titleLabel = label(AppText.settings, size: 22, weight: .semibold, color: primaryText)
        let closeButton = NSButton(title: "", target: self, action: #selector(cancel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let tabLabels = [
            AppText.localized("基础", "General"),
            AppText.localized("模型", "Model"),
            AppText.localized("AI 分析", "AI Analysis"),
            AppText.localized("朗读", "Read Aloud"),
            AppText.localized("缓存", "Cache")
        ]
        let sidebarControl = SettingsTabsView(
            labels: tabLabels,
            selectedIndex: initialTab.rawValue,
            style: .sidebar
        )
        sidebarControl.onSelectionChanged = { [weak self] index in
            self?.settingsTabChanged(index: index)
        }
        sidebarControl.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NonScrollingSettingsScrollView()
        scrollView.identifier = Identifiers.settingsFormSurface
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = formBackground.cgColor
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = settingsBorderColor(for: theme).cgColor
        scrollView.layer?.cornerRadius = 12
        scrollView.layer?.masksToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = VerticalOnlyClipView()
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = formBackground

        let formContent = NSView()
        formContent.identifier = Identifiers.settingsFormSurface
        formContent.wantsLayer = true
        formContent.layer?.backgroundColor = formBackground.cgColor
        formContent.translatesAutoresizingMaskIntoConstraints = false
        formContent.setContentHuggingPriority(.required, for: .horizontal)
        formContent.setContentCompressionResistancePriority(.required, for: .horizontal)
        scrollView.documentView = formContent

        let basicPage = themedPage(backgroundColor: formBackground)
        let modelPage = themedPage(backgroundColor: formBackground)
        let embeddingPage = themedPage(backgroundColor: formBackground)
        let speechPage = themedPage(backgroundColor: formBackground)
        let cachePage = themedPage(backgroundColor: formBackground)
        for page in [basicPage, modelPage, embeddingPage, speechPage, cachePage] {
            formContent.addSubview(page)
        }
        modelPage.isHidden = true
        embeddingPage.isHidden = true
        speechPage.isHidden = true
        cachePage.isHidden = true

        let speechSection = makeSpeechSection(
            settingsFontSize: settingsFontSize,
            primaryText: primaryText,
            secondaryText: secondaryText
        )
        let speechRuntimePopup = speechSection.runtimePopup
        let speechVoicePopup = speechSection.voicePopup
        let speechSpeedPopup = speechSection.speedPopup

        let cacheSection = makeCacheSection(
            settingsFontSize: settingsFontSize,
            primaryText: primaryText,
            secondaryText: secondaryText
        )
        let cacheStatusLabel = cacheSection.cacheStatusLabel
        let currentIndexStatusLabel = cacheSection.currentIndexStatusLabel

        let cancelButton = settingsActionButton(title: AppText.cancel, target: self, action: #selector(cancel(_:)))
        let saveButton = settingsActionButton(title: AppText.confirm, target: self, action: #selector(save(_:)), isPrimary: true)
        saveButton.keyEquivalent = "\r"

        for view in [titleIcon, titleLabel, closeButton, sidebarControl, scrollView, cancelButton, saveButton] {
            content.addSubview(view)
        }
        // The General and Model pages are SwiftUI, hosted inside the existing
        // panel so the tabs, Save and Cancel keep working unchanged.
        installGeneralSettingsPage(in: basicPage)
        installModelSettingsPage(in: modelPage)
        installEmbeddingSettingsPage(in: embeddingPage)
        for view in speechSection.pageViews {
            speechPage.addSubview(view)
        }
        for view in cacheSection.pageViews {
            cachePage.addSubview(view)
        }

        let labelColumnWidth = layout.labelColumnWidth
        let fieldWidth = layout.fieldWidth
        let formWidth = layout.formWidth
        let controlHeight = layout.controlHeight
        NSLayoutConstraint.activate(speechConstraints(
            for: speechSection,
            page: speechPage,
            labelColumnWidth: labelColumnWidth,
            fieldWidth: fieldWidth,
            controlHeight: controlHeight
        ))
        NSLayoutConstraint.activate(cacheConstraints(
            for: cacheSection,
            page: cachePage,
            formWidth: formWidth
        ))
        NSLayoutConstraint.activate([
            titleIcon.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            titleIcon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 38),
            titleIcon.widthAnchor.constraint(equalToConstant: layout.titleIconSize),
            titleIcon.heightAnchor.constraint(equalToConstant: layout.titleIconSize),
            titleLabel.centerYAnchor.constraint(equalTo: titleIcon.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleIcon.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -54),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            sidebarControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 96),
            sidebarControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            sidebarControl.widthAnchor.constraint(equalToConstant: 148),
            sidebarControl.bottomAnchor.constraint(lessThanOrEqualTo: saveButton.topAnchor, constant: -22),

            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 96),
            scrollView.leadingAnchor.constraint(equalTo: sidebarControl.trailingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -22),
            formContent.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 22),
            formContent.centerXAnchor.constraint(equalTo: scrollView.contentView.centerXAnchor),
            formContent.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.leadingAnchor),
            formContent.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.contentView.trailingAnchor),
            formContent.widthAnchor.constraint(equalToConstant: formWidth),
            formContent.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            basicPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            basicPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            basicPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            basicPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            modelPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            modelPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            modelPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            modelPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            embeddingPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            embeddingPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            embeddingPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            embeddingPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            speechPage.topAnchor.constraint(equalTo: formContent.topAnchor),
            speechPage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            speechPage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            speechPage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),
            cachePage.topAnchor.constraint(equalTo: formContent.topAnchor),
            cachePage.leadingAnchor.constraint(equalTo: formContent.leadingAnchor),
            cachePage.trailingAnchor.constraint(equalTo: formContent.trailingAnchor),
            cachePage.bottomAnchor.constraint(equalTo: formContent.bottomAnchor),

            // The General and Model pages are SwiftUI now; their hosting views
            // size the pages, so the old per-control constraints are gone with
            // the controls.

            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -36),
            saveButton.widthAnchor.constraint(equalToConstant: 104),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 104),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        self.panel = panel
        self.settingsTabControl = nil
        self.settingsSidebarControl = sidebarControl
        self.settingsScrollView = scrollView
        self.basicPage = basicPage
        self.modelPage = modelPage
        self.embeddingPage = embeddingPage
        self.speechPage = speechPage
        self.cachePage = cachePage
        self.speechRuntimePopup = speechRuntimePopup
        self.speechVoicePopup = speechVoicePopup
        self.speechSpeedPopup = speechSpeedPopup
        self.speechRuntimeControls = Dictionary(uniqueKeysWithValues: speechSection.runtimeRows.map { ($0.runtime, $0) })
        self.cacheStatusLabel = cacheStatusLabel
        self.currentIndexStatusLabel = currentIndexStatusLabel
        refreshSpeechRuntimeStatus()
        settingsTabChanged(index: initialTab.rawValue)

        installAppActivationObserver()
        refreshVectorCacheStatus()
        startCacheRefreshTimer()
        showPanel(panel, attachedTo: window)
        DispatchQueue.main.async {
            panel.makeKey()
        }
    }
}
