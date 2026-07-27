import Cocoa
import SwiftUI
import LeafReaderCore

private struct VocabularyPanelViews {
    let header: NSView
    let filterControl: SettingsTabsView
    let reviewContainer: NSView
    let listView: NSView
    let reviewPriorityPopup: NSPopUpButton
    let reviewGoalPopup: NSPopUpButton
    let exportMarkdownButton: ThemedSettingsActionButton
    let exportCSVButton: ThemedSettingsActionButton
    let closeButton: ThemedSettingsActionButton
}

extension VocabularyPanelController {
    static let filterControlWidth: CGFloat = 360

    func makePanel(records: [VocabularyExportRecord]) -> NSWindow? {
        guard let owner else { return nil }
        let panel = makeWindow()
        let theme = ReaderTheme.selected
        let root = makeRootView(for: panel, theme: theme)
        panel.contentView = root

        let views = makePanelViews(owner: owner, records: records, theme: theme)
        addPanelViews(views, to: root)
        installPanelConstraints(views, in: root)
        return panel
    }

    private func makeWindow() -> NSWindow {
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = true
        return panel
    }

    private func makeRootView(for panel: NSWindow, theme: ReaderTheme) -> NSView {
        guard let owner else { return NSView() }
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = owner.vocabularyPanelBackgroundColor(for: theme).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = owner.vocabularyBorderColor(for: theme).cgColor
        root.layer?.masksToBounds = false
        root.layer?.shadowColor = NSColor.black.cgColor
        root.layer?.shadowOpacity = theme == .dark ? 0.42 : 0.24
        root.layer?.shadowRadius = 32
        root.layer?.shadowOffset = CGSize(width: 0, height: -12)
        root.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        root.autoresizingMask = [.width, .height]
        root.translatesAutoresizingMaskIntoConstraints = true
        return root
    }

    private func makePanelViews(
        owner: ReaderWindowController,
        records: [VocabularyExportRecord],
        theme: ReaderTheme
    ) -> VocabularyPanelViews {
        let panelBackground = owner.vocabularyPanelBackgroundColor(for: theme)

        let initialFilter = owner.vocabularyReviewSession.filter
        let isListMode = owner.vocabularyReviewSession.listModeEnabled
        let filterControl = makeFilterControl(
            owner: owner,
            selectedIndex: isListMode ? segmentIndex(for: initialFilter) : 0
        )
        headerModel.summary = owner.vocabularySummaryText(records: records, filter: initialFilter)
        headerModel.apply(stats: VocabularyLearningStatsCalculator.stats(records: records))
        let header = makeHeader(theme: theme)
        let listView = makeVocabularyList(theme: theme)
        let reviewContainer = makeReviewContainer(panelBackground: panelBackground)
        listModel.action = { [weak owner] action in owner?.handleVocabularyListAction(action) }
        owner.populateVocabularyList(records: records, filter: initialFilter)
        owner.populateVocabularyReviewContainer(reviewContainer, records: records, filter: initialFilter, isDark: theme == .dark, autoPlayNewCard: false)
        listView.isHidden = !isListMode
        reviewContainer.isHidden = isListMode

        let reviewPriorityPopup = owner.vocabularyReviewPriorityPopup()
        reviewPriorityPopup.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewPriorityPopup")
        reviewPriorityPopup.isHidden = isListMode
        let reviewGoalPopup = owner.vocabularyDailyGoalPopup()
        reviewGoalPopup.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewGoalPopup")
        reviewGoalPopup.isHidden = isListMode

        let closeButton = owner.vocabularyActionButton(title: AppText.close, target: owner, action: #selector(ReaderWindowController.closeVocabularyBook(_:)))
        closeButton.identifier = NSUserInterfaceItemIdentifier("closeVocabularyBook")

        let exportMarkdownButton = owner.vocabularyActionButton(
            title: AppText.localized("导出 MD", "Export MD"),
            target: owner,
            action: #selector(ReaderWindowController.exportVocabularyMarkdown(_:))
        )
        exportMarkdownButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportMarkdownButton")
        exportMarkdownButton.isHidden = !isListMode

        let exportCSVButton = owner.vocabularyActionButton(
            title: AppText.localized("导出 Anki CSV", "Export Anki CSV"),
            target: owner,
            action: #selector(ReaderWindowController.exportVocabularyCSV(_:))
        )
        exportCSVButton.identifier = NSUserInterfaceItemIdentifier("vocabularyExportCSVButton")
        exportCSVButton.isHidden = !isListMode

        return VocabularyPanelViews(
            header: header,
            filterControl: filterControl,
            reviewContainer: reviewContainer,
            listView: listView,
            reviewPriorityPopup: reviewPriorityPopup,
            reviewGoalPopup: reviewGoalPopup,
            exportMarkdownButton: exportMarkdownButton,
            exportCSVButton: exportCSVButton,
            closeButton: closeButton
        )
    }

    /// One hosting view for the icon, title, summary line and stat cards.
    private func makeHeader(theme: ReaderTheme) -> NSView {
        let hosting = NSHostingView(rootView: VocabularyTrainerHeaderView(
            model: headerModel,
            theme: theme,
            // The filter tabs sit over the header's top-right corner.
            reservedTrailingWidth: Self.filterControlWidth + 16
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.setAccessibilityIdentifier(VocabularyTrainerAccessibility.header)
        return hosting
    }

    private func makeFilterControl(owner: ReaderWindowController, selectedIndex: Int) -> SettingsTabsView {
        let filterControl = SettingsTabsView(
            labels: [
                AppText.localized("背单词", "Review"),
                AppText.localized("复习", "Reviewed"),
                AppText.localized("新词", "New"),
                AppText.localized("全部", "All")
            ],
            selectedIndex: selectedIndex
        )
        filterControl.onSelectionChanged = { [weak owner] index in
            owner?.changeVocabularyTab(index: index)
        }
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        return filterControl
    }

    private func segmentIndex(for filter: VocabularyFilter) -> Int {
        switch filter {
        case .due: return 1
        case .new: return 2
        case .all: return 3
        }
    }

    private func makeVocabularyList(theme: ReaderTheme) -> NSView {
        let hosting = NSHostingView(rootView: VocabularyWordListView(model: listModel, theme: theme))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Both: `findView(identifier:)` searches `NSView.identifier`, while the
        // smoke test reads the accessibility identifier. Setting only the latter
        // left the list permanently hidden, because the show/hide toggle could
        // not find it.
        hosting.identifier = NSUserInterfaceItemIdentifier("vocabularyList")
        hosting.setAccessibilityIdentifier("vocabularyList")
        return hosting
    }

    private func makeReviewContainer(panelBackground: NSColor) -> NSView {
        let reviewContainer = NSView()
        reviewContainer.wantsLayer = true
        reviewContainer.layer?.backgroundColor = panelBackground.cgColor
        reviewContainer.identifier = NSUserInterfaceItemIdentifier("vocabularyReviewContainer")
        reviewContainer.translatesAutoresizingMaskIntoConstraints = false
        return reviewContainer
    }

    private func addPanelViews(_ views: VocabularyPanelViews, to root: NSView) {
        [
            views.header,
            views.filterControl,
            views.reviewContainer,
            views.listView,
            views.reviewPriorityPopup,
            views.reviewGoalPopup,
            views.exportMarkdownButton,
            views.exportCSVButton,
            views.closeButton
        ].forEach(root.addSubview)
    }

    private func installPanelConstraints(_ views: VocabularyPanelViews, in root: NSView) {
        NSLayoutConstraint.activate([
            views.header.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            views.header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.filterControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.filterControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            views.filterControl.widthAnchor.constraint(equalToConstant: Self.filterControlWidth),
            views.filterControl.heightAnchor.constraint(equalToConstant: 30),

            views.reviewContainer.topAnchor.constraint(equalTo: views.header.bottomAnchor, constant: 12),
            views.reviewContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.reviewContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.reviewContainer.bottomAnchor.constraint(equalTo: views.closeButton.topAnchor, constant: -14),

            views.listView.topAnchor.constraint(equalTo: views.header.bottomAnchor, constant: 12),
            views.listView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.listView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.listView.bottomAnchor.constraint(equalTo: views.closeButton.topAnchor, constant: -14),

            views.reviewPriorityPopup.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.reviewPriorityPopup.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.reviewPriorityPopup.widthAnchor.constraint(equalToConstant: 150),
            views.reviewPriorityPopup.heightAnchor.constraint(equalToConstant: 36),
            views.reviewGoalPopup.leadingAnchor.constraint(equalTo: views.reviewPriorityPopup.trailingAnchor, constant: 10),
            views.reviewGoalPopup.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.reviewGoalPopup.widthAnchor.constraint(equalToConstant: 112),
            views.reviewGoalPopup.heightAnchor.constraint(equalToConstant: 36),

            views.exportMarkdownButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            views.exportMarkdownButton.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.exportMarkdownButton.widthAnchor.constraint(equalToConstant: 104),
            views.exportMarkdownButton.heightAnchor.constraint(equalToConstant: 36),
            views.exportCSVButton.leadingAnchor.constraint(equalTo: views.exportMarkdownButton.trailingAnchor, constant: 10),
            views.exportCSVButton.centerYAnchor.constraint(equalTo: views.closeButton.centerYAnchor),
            views.exportCSVButton.widthAnchor.constraint(equalToConstant: 132),
            views.exportCSVButton.heightAnchor.constraint(equalToConstant: 36),

            views.closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            views.closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            views.closeButton.widthAnchor.constraint(equalToConstant: 104),
            views.closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
}
