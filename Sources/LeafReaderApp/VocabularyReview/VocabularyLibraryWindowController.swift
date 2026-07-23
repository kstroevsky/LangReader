import Cocoa
import SwiftUI

/// A vertical stack that anchors its content to the top of its scroll view.
///
/// An unflipped `NSScrollView` document view whose content is shorter than the
/// visible area sinks to the bottom-left. Flipping the coordinate space — as
/// `NSTableView` does — makes the content grow downward from the top edge, which
/// is what the detail pane wants when a word has only a few occurrences.
final class VocabularyLibraryWindowController: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    private weak var owner: ReaderWindowController?
    private let reloadTask = DebouncedTask(delay: 0.12)
    private let rootView = NSView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let sourcePopup = NSPopUpButton()
    private let sortPopup = NSPopUpButton()
    private let listModel = VocabularyLibraryListModel()
    private let detailModel = VocabularyDetailModel()
    private(set) var window: NSWindow?
    private var records: [VocabularyLibraryRecord] = []
    private var filteredRecords: [VocabularyLibraryRecord] = []
    /// True once records have been delivered at least once, so a re-open shows
    /// the last-known list instantly instead of the loading placeholder.
    private var hasLoadedOnce = false
    /// A surface-form key to select once records arrive, set when the window is
    /// opened focused on a specific word (from the Assistant's Occurrences
    /// button). Resolved against the records because a word is filed under its
    /// lemma, which the caller may not know.
    private var pendingFocusWordKey: String?

    init(owner: ReaderWindowController) {
        self.owner = owner
        super.init()
        configureDetailModel()
    }

    deinit {
        reloadTask.cancel()
    }

    /// Shows the window immediately, before records are computed, so the click
    /// is never blocked by the library scan. The first open displays a loading
    /// placeholder; re-opens keep the last-known list visible until the
    /// background refresh delivers fresh records via `apply(records:)`.
    func present(focusWordKey: String? = nil) {
        if let focusWordKey, !focusWordKey.isEmpty {
            pendingFocusWordKey = focusWordKey
            // A lingering search or source filter could hide the focused word.
            searchField.stringValue = ""
            if sourcePopup.numberOfItems > 0 { sourcePopup.selectItem(at: 0) }
            // The window may already be showing records; focus them now rather
            // than waiting for the background refresh to round-trip.
            if hasLoadedOnce { focusPendingWordIfPossible() }
        }
        if window == nil {
            buildWindow()
        }
        if !hasLoadedOnce {
            summaryLabel.stringValue = AppText.localized("正在载入…", "Loading…")
            showLoadingDetail()
        }
        if let window, (window.contentView?.bounds.height ?? 0) < 500 {
            window.setContentSize(NSSize(width: max(window.contentView?.bounds.width ?? 0, 960), height: 680))
            window.contentView?.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
            window.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.frame.height < 540 else { return }
            window.setContentSize(NSSize(width: max(window.frame.width, 960), height: 680))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Populates the window with freshly computed records. Safe to call while
    /// the window is closed — it simply no-ops until one has been built.
    func apply(records: [VocabularyLibraryRecord]) {
        guard window != nil else { return }
        hasLoadedOnce = true
        let focusID = pendingFocusWordKey.flatMap { Self.recordID(in: records, forWordKey: $0) }
        pendingFocusWordKey = nil
        update(records: records, focusID: focusID)
    }

    private func focusPendingWordIfPossible() {
        guard let key = pendingFocusWordKey,
              let id = Self.recordID(in: records, forWordKey: key) else { return }
        pendingFocusWordKey = nil
        applyFilters(preferredSelectionID: id)
    }

    /// The record a focus word belongs to. A word is filed under its lemma, so
    /// try the lemma key first, then the display word, then any observed form —
    /// the caller passes the surface spelling and need not know the lemma.
    static func recordID(in records: [VocabularyLibraryRecord], forWordKey key: String) -> String? {
        guard !key.isEmpty else { return nil }
        if let exact = records.first(where: { $0.id == key }) { return exact.id }
        if let byWord = records.first(where: {
            VocabularyTextPolicy.canonicalVocabularyKey($0.word) == key
        }) { return byWord.id }
        return records.first(where: { record in
            record.forms.contains { VocabularyTextPolicy.canonicalVocabularyKey($0.surface) == key }
        })?.id
    }

    private func showLoadingDetail() {
        detailModel.record = nil
    }

    func close() {
        window?.close()
    }

    func scheduleReload() {
        reloadTask.schedule { [weak self] in
            guard let self, self.window?.isVisible == true, let owner = self.owner else { return }
            owner.reloadVocabularyLibraryInBackground()
        }
    }

    func refreshTheme() {
        guard window != nil else { return }
        applyTheme()
        listModel.theme = ReaderTheme.selected
        syncDetail()
    }

    private func buildWindow() {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.localized("生词", "Words")
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        rootView.frame = NSRect(x: 0, y: 0, width: 1080, height: 720)
        rootView.autoresizingMask = [.width, .height]
        panel.contentView = rootView
        // Fit the display rather than assuming a fixed size: a hard 1080x720
        // with a 960 minimum leaves the window unusable — and unshrinkable —
        // on smaller screens.
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1080, height: 720)
        panel.minSize = NSSize(
            width: min(820, visible.width),
            height: min(560, visible.height)
        )
        panel.maxSize = NSSize(width: visible.width, height: visible.height)
        panel.setContentSize(
            NSSize(
                width: min(1080, visible.width - 40),
                height: min(720, visible.height - 40)
            )
        )
        panel.center()

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "text.word.spacing", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 25, weight: .semibold))
        icon.imageScaling = .scaleNone

        let title = NSTextField(labelWithString: AppText.localized("生词", "Words"))
        title.font = AppFont.semibold(ofSize: 24)

        summaryLabel.font = NSFont.systemFont(ofSize: 13)
        summaryLabel.lineBreakMode = .byTruncatingTail

        searchField.placeholderString = AppText.localized("搜索单词、释义或上下文", "Search words, definitions, or context")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true

        sourcePopup.target = self
        sourcePopup.action = #selector(filterChanged(_:))
        sourcePopup.toolTip = AppText.localized("按来源文件筛选", "Filter by source document")

        sortPopup.addItems(withTitles: [
            AppText.localized("最近添加", "Recently added"),
            AppText.localized("按字母排序", "Alphabetical")
        ])
        sortPopup.target = self
        sortPopup.action = #selector(filterChanged(_:))

        let refreshButton = owner?.vocabularyActionButton(
            title: AppText.localized("刷新", "Refresh"),
            target: self,
            action: #selector(refreshTapped(_:)),
            fontSize: 13
        ) ?? NSButton(title: AppText.localized("刷新", "Refresh"), target: self, action: #selector(refreshTapped(_:)))

        let listScroll = makeListView()
        let detailScroll = makeDetailView()
        let divider = NSBox()
        divider.boxType = .separator

        for view in [icon, title, summaryLabel, searchField, sourcePopup, sortPopup, refreshButton, listScroll, divider, detailScroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 28),
            icon.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            summaryLabel.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 14),
            summaryLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: searchField.leadingAnchor, constant: -18),

            refreshButton.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            refreshButton.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 82),
            refreshButton.heightAnchor.constraint(equalToConstant: 30),
            sortPopup.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),
            sortPopup.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            sortPopup.widthAnchor.constraint(equalToConstant: 132),
            sourcePopup.trailingAnchor.constraint(equalTo: sortPopup.leadingAnchor, constant: -8),
            sourcePopup.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            sourcePopup.widthAnchor.constraint(equalToConstant: 170),
            searchField.trailingAnchor.constraint(equalTo: sourcePopup.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 238),

            listScroll.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 22),
            listScroll.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            listScroll.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -24),
            listScroll.widthAnchor.constraint(equalToConstant: 310),
            listScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 500),
            divider.topAnchor.constraint(equalTo: listScroll.topAnchor),
            divider.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 18),
            divider.widthAnchor.constraint(equalToConstant: 1),
            detailScroll.topAnchor.constraint(equalTo: listScroll.topAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 24),
            detailScroll.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            detailScroll.bottomAnchor.constraint(equalTo: listScroll.bottomAnchor)
        ])

        window = panel
        applyTheme()
    }

    private func makeListView() -> NSView {
        listModel.onSelect = { [weak self] _ in
            self?.syncDetail()
        }
        let hosting = NSHostingView(rootView: VocabularyLibraryListView(model: listModel))
        return hosting
    }

    private func makeDetailView() -> NSView {
        NSHostingView(rootView: VocabularyDetailView(model: detailModel))
    }

    private func applyTheme() {
        let theme = ReaderTheme.selected
        let background = theme.vocabularyPanelBackgroundColor
        // Force the appearance to match the app's theme rather than inheriting
        // the system's. Without this, a light theme on a machine set to Dark mode
        // leaves nil (= inherit dark), so system controls like the form-filter
        // NSSegmentedControl draw light text on the window's forced-light
        // background — invisible labels.
        window?.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        window?.backgroundColor = background
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = background.cgColor
        summaryLabel.textColor = theme.vocabularySecondaryTextColor
        listModel.theme = theme
        owner?.styleVocabularyActionButtons(in: rootView)
    }

    private func update(records: [VocabularyLibraryRecord], focusID: String? = nil) {
        let selectedID = focusID ?? selectedRecord?.id
        let selectedSource = sourcePopup.selectedItem?.representedObject as? String
        self.records = records
        rebuildSourcePopup(selectedPath: selectedSource)
        applyFilters(preferredSelectionID: selectedID)
    }

    private func rebuildSourcePopup(selectedPath: String?) {
        let sources = Dictionary(grouping: records.flatMap(\.occurrences)) {
            $0.documentURL.standardizedFileURL.path
        }.compactMap { path, occurrences -> (String, String)? in
            guard let first = occurrences.first else { return nil }
            return (path, first.documentTitle)
        }.sorted {
            $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending
        }

        sourcePopup.removeAllItems()
        sourcePopup.addItem(withTitle: AppText.localized("所有文件", "All documents"))
        sourcePopup.lastItem?.representedObject = nil
        for source in sources {
            sourcePopup.addItem(withTitle: source.1)
            sourcePopup.lastItem?.representedObject = source.0
            sourcePopup.lastItem?.toolTip = source.0
        }
        if let selectedPath,
           let index = sourcePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == selectedPath }) {
            sourcePopup.selectItem(at: index)
        }
    }

    private func applyFilters(preferredSelectionID: String? = nil) {
        // Read the controls, then hand off: the rules live in
        // `VocabularyLibraryFilter` where they can be tested.
        let selectionID = preferredSelectionID ?? selectedRecord?.id
        filteredRecords = VocabularyLibraryFilter.apply(
            records: records,
            query: searchField.stringValue,
            sourcePath: sourcePopup.selectedItem?.representedObject as? String,
            sortOrder: VocabularyLibraryFilter.SortOrder(rawValue: sortPopup.indexOfSelectedItem) ?? .recent
        )

        summaryLabel.stringValue = VocabularyLibraryFilter.summaryText(
            matchCount: filteredRecords.count,
            totalCount: records.count
        )
        let row = VocabularyLibraryFilter.selectionRow(in: filteredRecords, preferredID: selectionID)
        listModel.theme = ReaderTheme.selected
        listModel.apply(records: filteredRecords, selectedID: row.map { filteredRecords[$0].id })
        // A stable selection keeps its form tab: `syncDetail` sets the same
        // record, and the model only resets the tab when the record id changes.
        syncDetail()
    }

    private var selectedRecord: VocabularyLibraryRecord? {
        listModel.selectedRecord
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilters(preferredSelectionID: selectedRecord?.id)
    }

    @objc private func filterChanged(_ sender: Any?) {
        applyFilters(preferredSelectionID: selectedRecord?.id)
    }

    @objc private func refreshTapped(_ sender: Any?) {
        owner?.reloadVocabularyLibraryInBackground()
    }

    // MARK: Detail pane (SwiftUI)

    /// Wires the detail model's actions and rich-text producers to the
    /// controller. The two markdown renderers stay in AppKit; the model bridges
    /// their output to SwiftUI, so the pane reads identically to the one it
    /// replaced without re-implementing markdown.
    private func configureDetailModel() {
        detailModel.onCopy = { [weak self] in
            guard let word = self?.selectedRecord?.word else { return }
            self?.owner?.copyTextToClipboard(word)
        }
        detailModel.onRemove = { [weak self] in
            self?.confirmRemoveSelectedWord()
        }
        detailModel.onOpenSource = { [weak self] occurrence in
            self?.owner?.openVocabularyLibraryOccurrence(occurrence)
        }
        detailModel.makeAnswer = { text in
            MarkdownRenderer.render(text, fontSize: 15, textColor: ReaderTheme.selected.vocabularyBodyTextColor)
        }
        detailModel.makeContext = { [weak self] text, word in
            self?.owner?.vocabularyExampleAttributedString(
                text, word: word, fontSize: 14, textColor: ReaderTheme.selected.vocabularyBodyTextColor
            ) ?? NSAttributedString(string: text)
        }
    }

    /// Pushes the current selection, source filter and theme into the detail
    /// model. SwiftUI diffs the result, so this is cheap to call on every list
    /// change — the per-keystroke-rebuild guard the AppKit pane needed is gone.
    private func syncDetail() {
        detailModel.theme = ReaderTheme.selected
        detailModel.sourcePath = sourcePopup.selectedItem?.representedObject as? String
        detailModel.record = selectedRecord
    }

    private func confirmRemoveSelectedWord() {
        guard let record = selectedRecord, let owner else { return }
        let occurrenceCount = record.occurrences.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppText.localized("删除“\(record.word)”？", "Remove “\(record.word)”?")
        alert.informativeText = record.sourceCount > 1
            ? AppText.localized(
                "将从 \(record.sourceCount) 个文件中删除该单词及其 \(occurrenceCount) 处出处。此操作无法撤销。",
                "This removes the word and all \(occurrenceCount) occurrences from \(record.sourceCount) documents. This cannot be undone."
            )
            : AppText.localized(
                "将删除该单词及其 \(occurrenceCount) 处出处。此操作无法撤销。",
                "This removes the word and all \(occurrenceCount) occurrences. This cannot be undone."
            )
        alert.addButton(withTitle: AppText.localized("删除", "Remove"))
        alert.addButton(withTitle: AppText.localized("取消", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true

        let confirm: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            owner.deleteVocabularyLibraryRecord(record)
            // Optimistic removal keeps the list responsive; the background
            // reload reconciles against the store immediately after.
            self.records.removeAll { $0.id == record.id }
            self.applyFilters()
            owner.reloadVocabularyLibraryInBackground()
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: confirm)
        } else {
            confirm(alert.runModal())
        }
    }
}
