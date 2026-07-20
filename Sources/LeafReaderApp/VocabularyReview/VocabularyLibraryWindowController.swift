import Cocoa

final class VocabularyLibrarySourceButton: NSButton {
    var occurrence: VocabularyLibraryOccurrence?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// A vertical stack that anchors its content to the top of its scroll view.
///
/// An unflipped `NSScrollView` document view whose content is shorter than the
/// visible area sinks to the bottom-left. Flipping the coordinate space — as
/// `NSTableView` does — makes the content grow downward from the top edge, which
/// is what the detail pane wants when a word has only a few occurrences.
private final class TopAnchoredStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class VocabularyLibraryWordCell: NSTableCellView {
    private let wordLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let answerLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wordLabel.font = AppFont.semibold(ofSize: 16)
        wordLabel.lineBreakMode = .byTruncatingTail
        answerLabel.font = NSFont.systemFont(ofSize: 12)
        answerLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.font = AppFont.semibold(ofSize: 11)
        metadataLabel.alignment = .right
        metadataLabel.lineBreakMode = .byTruncatingTail

        for label in [wordLabel, answerLabel, metadataLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            wordLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            wordLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: metadataLabel.leadingAnchor, constant: -8),
            metadataLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            metadataLabel.centerYAnchor.constraint(equalTo: wordLabel.centerYAnchor),
            metadataLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 128),
            answerLabel.leadingAnchor.constraint(equalTo: wordLabel.leadingAnchor),
            answerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            answerLabel.topAnchor.constraint(equalTo: wordLabel.bottomAnchor, constant: 5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(record: VocabularyLibraryRecord, theme: ReaderTheme) {
        wordLabel.stringValue = record.word
        let sourceText = record.sourceCount == 1
            ? AppText.localized("1 个文件", "1 file")
            : AppText.localized("\(record.sourceCount) 个文件", "\(record.sourceCount) files")
        metadataLabel.stringValue = AppText.localized(
            "\(record.occurrences.count) 处 · \(sourceText)",
            "\(record.occurrences.count)x · \(sourceText)"
        )
        let answer = VocabularyAnswerSanitizer.removingTrailingTags(from: record.answer)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        answerLabel.stringValue = answer.isEmpty
            ? AppText.localized("没有释义", "No definition yet")
            : answer
        wordLabel.textColor = theme.vocabularyPrimaryTextColor
        metadataLabel.textColor = theme.vocabularySecondaryTextColor
        answerLabel.textColor = theme.vocabularySecondaryTextColor
    }
}

final class VocabularyLibraryWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum SortOrder: Int {
        case recent = 0
        case alphabetical = 1
    }

    private weak var owner: ReaderWindowController?
    private let reloadTask = DebouncedTask(delay: 0.12)
    private let rootView = NSView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let sourcePopup = NSPopUpButton()
    private let sortPopup = NSPopUpButton()
    private let tableView = NSTableView()
    private let detailStack = TopAnchoredStackView()
    private(set) var window: NSWindow?
    private var records: [VocabularyLibraryRecord] = []
    private var filteredRecords: [VocabularyLibraryRecord] = []
    /// Canonical key of the surface form the occurrence list is filtered to,
    /// or nil for all forms. Reset whenever a different word is selected.
    private var occurrenceFormFilter: String?
    /// Segment index -> form key, with index 0 reserved for "all".
    private var occurrenceFormKeys: [String] = []
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
        for view in detailStack.arrangedSubviews {
            detailStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let label = NSTextField(labelWithString: AppText.localized("正在载入生词…", "Loading words…"))
        label.font = AppFont.semibold(ofSize: 16)
        label.textColor = ReaderTheme.selected.vocabularySecondaryTextColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        detailStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true
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
        tableView.reloadData()
        refreshDetail()
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

        let listScroll = makeListScrollView()
        let detailScroll = makeDetailScrollView()
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

    private func makeListScrollView() -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 66
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = false
        tableView.focusRingType = .none

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = tableView
        return scroll
    }

    private func makeDetailScrollView() -> NSScrollView {
        detailStack.orientation = .vertical
        detailStack.alignment = .width
        detailStack.spacing = 12
        detailStack.edgeInsets = NSEdgeInsets(top: 4, left: 2, bottom: 18, right: 10)
        detailStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = detailStack
        NSLayoutConstraint.activate([
            detailStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            detailStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            detailStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }

    private func applyTheme() {
        let theme = ReaderTheme.selected
        let background = theme.vocabularyPanelBackgroundColor
        window?.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : nil
        window?.backgroundColor = background
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = background.cgColor
        summaryLabel.textColor = theme.vocabularySecondaryTextColor
        tableView.backgroundColor = background
        detailStack.wantsLayer = true
        detailStack.layer?.backgroundColor = background.cgColor
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
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let sourcePath = sourcePopup.selectedItem?.representedObject as? String

        filteredRecords = records.filter { record in
            let matchesSource = sourcePath == nil || record.occurrences.contains {
                $0.documentURL.standardizedFileURL.path == sourcePath
            }
            guard matchesSource else { return false }
            guard !query.isEmpty else { return true }
            let haystack = ([record.word, record.answer, record.dictionaryTags ?? ""] + record.forms.map(\.surface) + record.occurrences.flatMap {
                [$0.context, $0.documentTitle, $0.location]
            }).joined(separator: "\n")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return haystack.contains(query)
        }

        if SortOrder(rawValue: sortPopup.indexOfSelectedItem) == .recent {
            filteredRecords.sort {
                if $0.latestCreatedAt != $1.latestCreatedAt {
                    return $0.latestCreatedAt > $1.latestCreatedAt
                }
                return $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
        } else {
            filteredRecords.sort {
                $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
        }

        summaryLabel.stringValue = AppText.localized(
            "\(filteredRecords.count) / \(records.count) 个单词",
            "\(filteredRecords.count) of \(records.count) words"
        )
        tableView.reloadData()
        let selectionID = preferredSelectionID ?? selectedRecord?.id
        let row = selectionID.flatMap { id in filteredRecords.firstIndex { $0.id == id } } ?? (filteredRecords.isEmpty ? nil : 0)
        if let row {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
            refreshDetail()
        }
    }

    private var selectedRecord: VocabularyLibraryRecord? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < filteredRecords.count else { return nil }
        return filteredRecords[tableView.selectedRow]
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredRecords.count else { return nil }
        let cell = VocabularyLibraryWordCell()
        cell.configure(record: filteredRecords[row], theme: ReaderTheme.selected)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // A form filter belongs to one word; carrying it to the next selection
        // would silently hide occurrences of a word that has no such form.
        occurrenceFormFilter = nil
        refreshDetail()
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

    @objc private func copyWord(_ sender: NSButton) {
        guard let word = selectedRecord?.word else { return }
        owner?.copyTextToClipboard(word)
    }

    @objc private func removeWord(_ sender: Any?) {
        guard let record = selectedRecord, let owner else { return }

        let occurrenceCount = record.occurrences.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppText.localized(
            "删除“\(record.word)”？",
            "Remove “\(record.word)”?"
        )
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

    @objc private func openSource(_ sender: VocabularyLibrarySourceButton) {
        guard let occurrence = sender.occurrence else { return }
        owner?.openVocabularyLibraryOccurrence(occurrence)
    }

    private func refreshDetail() {
        for view in detailStack.arrangedSubviews {
            detailStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let record = selectedRecord else {
            addEmptyDetail()
            return
        }
        let theme = ReaderTheme.selected
        let sourcePath = sourcePopup.selectedItem?.representedObject as? String
        let occurrences = sourcePath.map { path in
            record.occurrences.filter { $0.documentURL.standardizedFileURL.path == path }
        } ?? record.occurrences

        let wordRow = NSStackView()
        wordRow.orientation = .horizontal
        wordRow.alignment = .centerY
        wordRow.spacing = 10
        let wordLabel = NSTextField(labelWithString: record.word)
        wordLabel.font = AppFont.semibold(ofSize: 30)
        wordLabel.textColor = theme.vocabularyPrimaryTextColor
        wordLabel.lineBreakMode = .byTruncatingTail
        let copyButton = owner?.vocabularyActionButton(
            title: AppText.localized("复制", "Copy"),
            target: self,
            action: #selector(copyWord(_:)),
            fontSize: 13
        ) ?? NSButton(title: AppText.localized("复制", "Copy"), target: self, action: #selector(copyWord(_:)))
        copyButton.widthAnchor.constraint(equalToConstant: 74).isActive = true
        copyButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let removeButton = owner?.vocabularyActionButton(
            title: AppText.localized("删除", "Remove"),
            target: self,
            action: #selector(removeWord(_:)),
            fontSize: 13
        ) ?? NSButton(title: AppText.localized("删除", "Remove"), target: self, action: #selector(removeWord(_:)))
        (removeButton as? ThemedSettingsActionButton)?.labelColor = .systemRed
        removeButton.widthAnchor.constraint(equalToConstant: 82).isActive = true
        removeButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        wordRow.addArrangedSubview(wordLabel)
        wordRow.addArrangedSubview(copyButton)
        wordRow.addArrangedSubview(removeButton)
        detailStack.addArrangedSubview(wordRow)
        wordRow.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true

        let metadataParts = [
            record.dictionaryTags,
            record.dictionaryFrequency.map { AppText.localized("词频 #\($0)", "Frequency #\($0)") },
            record.forms.count > 1
                ? AppText.localized("\(record.forms.count) 个词形", "\(record.forms.count) forms")
                : nil,
            AppText.localized("\(occurrences.count) 个出处", "\(occurrences.count) occurrences")
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let metadata = NSTextField(labelWithString: metadataParts.joined(separator: "  ·  "))
        metadata.font = AppFont.semibold(ofSize: 12)
        metadata.textColor = theme.vocabularySecondaryTextColor
        metadata.lineBreakMode = .byTruncatingTail
        metadata.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailStack.addArrangedSubview(metadata)
        metadata.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true

        let hasInformativeLabel = record.forms.contains { $0.label?.isInformative == true }
        if record.forms.count > 1 || hasInformativeLabel {
            let formsText = record.forms.map(\.displayText).joined(separator: "  ·  ")
            let formsLabel = NSTextField(labelWithString: AppText.localized(
                "词形：\(formsText)",
                "Forms: \(formsText)"
            ))
            formsLabel.font = NSFont.systemFont(ofSize: 12)
            formsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            formsLabel.textColor = theme.vocabularySecondaryTextColor
            formsLabel.maximumNumberOfLines = 0
            formsLabel.lineBreakMode = .byWordWrapping
            detailStack.addArrangedSubview(formsLabel)
            formsLabel.widthAnchor.constraint(
                equalTo: detailStack.widthAnchor,
                constant: -12
            ).isActive = true
        }

        if !record.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let answer = NSTextField(labelWithAttributedString: MarkdownRenderer.render(
                String(record.answer.prefix(2400)),
                fontSize: 15,
                textColor: theme.vocabularyBodyTextColor
            ))
            answer.maximumNumberOfLines = 0
            answer.lineBreakMode = .byWordWrapping
            answer.isSelectable = true
            detailStack.addArrangedSubview(answer)
            answer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            answer.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true
        }

        let separator = NSBox()
        separator.boxType = .separator
        detailStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true

        let formGroups = occurrenceFormGroups(record: record, occurrences: occurrences)
        // A filter kept from a previous render may name a form this word does
        // not have; fall back to showing everything rather than nothing.
        if let filter = occurrenceFormFilter, !formGroups.contains(where: { $0.key == filter }) {
            occurrenceFormFilter = nil
        }
        let visibleOccurrences: [VocabularyLibraryOccurrence]
        if let filter = occurrenceFormFilter {
            visibleOccurrences = occurrences.filter {
                VocabularyTextPolicy.canonicalVocabularyKey($0.surfaceForm ?? record.word) == filter
            }
        } else {
            visibleOccurrences = occurrences
        }

        if formGroups.count > 1 {
            let tabs = formFilterTabs(groups: formGroups, total: occurrences.count)
            detailStack.addArrangedSubview(tabs)
            tabs.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true
        }

        let occurrencesTitle = NSTextField(labelWithString: AppText.localized("出处与上下文", "Occurrences & context"))
        occurrencesTitle.font = AppFont.semibold(ofSize: 17)
        occurrencesTitle.textColor = theme.vocabularyPrimaryTextColor
        occurrencesTitle.lineBreakMode = .byTruncatingTail
        occurrencesTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailStack.addArrangedSubview(occurrencesTitle)
        occurrencesTitle.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true

        for occurrence in visibleOccurrences {
            let view = occurrenceView(occurrence, word: occurrence.surfaceForm ?? record.word, theme: theme)
            detailStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true
        }
    }

    private func addEmptyDetail() {
        let label = NSTextField(labelWithString: records.isEmpty
            ? AppText.localized("还没有保存的单词。\n在文档中选择一个单词即可开始。", "No saved words yet.\nSelect a word in a document to get started.")
            : AppText.localized("没有符合筛选条件的单词。", "No words match these filters."))
        label.font = AppFont.semibold(ofSize: 16)
        label.textColor = ReaderTheme.selected.vocabularySecondaryTextColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        detailStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true
    }

    private struct OccurrenceFormGroup {
        let key: String
        let surface: String
        let label: GermanFormLabel?
        let count: Int
    }

    /// Groups occurrences by the exact spelling that was highlighted.
    ///
    /// Counts come from the occurrences themselves rather than the record's
    /// form list, so every tab's number matches the rows it reveals.
    private func occurrenceFormGroups(
        record: VocabularyLibraryRecord,
        occurrences: [VocabularyLibraryOccurrence]
    ) -> [OccurrenceFormGroup] {
        var labelsByKey: [String: GermanFormLabel] = [:]
        for form in record.forms {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(form.surface)
            if let label = form.label, labelsByKey[key] == nil {
                labelsByKey[key] = label
            }
        }

        var order: [String] = []
        var surfaces: [String: String] = [:]
        var counts: [String: Int] = [:]
        for occurrence in occurrences {
            let surface = occurrence.surfaceForm ?? record.word
            let key = VocabularyTextPolicy.canonicalVocabularyKey(surface)
            guard !key.isEmpty else { continue }
            if counts[key] == nil {
                order.append(key)
                surfaces[key] = surface
            }
            counts[key, default: 0] += 1
        }
        return order.map { key in
            OccurrenceFormGroup(
                key: key,
                surface: surfaces[key] ?? key,
                label: labelsByKey[key],
                count: counts[key] ?? 0
            )
        }
    }

    /// Tabs that filter the occurrence list down to a single inflected form.
    ///
    /// Wrapped in a horizontal scroller: a word with many forms would otherwise
    /// make the control wider than the pane, which is what pushed this window
    /// past the edge of the screen before.
    private func formFilterTabs(groups: [OccurrenceFormGroup], total: Int) -> NSView {
        let theme = ReaderTheme.selected
        var titles = [AppText.localized("全部（\(total)）", "All (\(total))")]
        occurrenceFormKeys = [""]
        for group in groups {
            titles.append("\(group.surface) (\(group.count))")
            occurrenceFormKeys.append(group.key)
        }

        let segmented = NSSegmentedControl(
            labels: titles,
            trackingMode: .selectOne,
            target: self,
            action: #selector(occurrenceFormFilterChanged(_:))
        )
        segmented.segmentDistribution = .fit
        segmented.selectedSegment = occurrenceFormFilter
            .flatMap { occurrenceFormKeys.firstIndex(of: $0) } ?? 0
        segmented.translatesAutoresizingMaskIntoConstraints = false
        for (index, group) in groups.enumerated() {
            segmented.setToolTip(
                group.label?.displayName ?? group.surface,
                forSegment: index + 1
            )
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(segmented)
        scroll.documentView = documentView

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        _ = theme

        NSLayoutConstraint.activate([
            segmented.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            segmented.topAnchor.constraint(equalTo: documentView.topAnchor),
            segmented.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 30)
        ])
        // The width constraint against detailStack is applied by the caller,
        // after this view is added to the stack — activating it here would
        // reference a view with no common ancestor and throw.
        return container
    }

    @objc private func occurrenceFormFilterChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard index > 0, index < occurrenceFormKeys.count else {
            occurrenceFormFilter = nil
            refreshDetail()
            return
        }
        occurrenceFormFilter = occurrenceFormKeys[index]
        refreshDetail()
    }

    private func occurrenceView(_ occurrence: VocabularyLibraryOccurrence, word: String, theme: ReaderTheme) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = theme.vocabularyCardBackgroundColor.cgColor
        card.layer?.borderColor = theme.vocabularyCardBorderColor.cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false

        let sourceButton = VocabularyLibrarySourceButton(title: occurrence.documentTitle, target: self, action: #selector(openSource(_:)))
        sourceButton.occurrence = occurrence
        sourceButton.isBordered = false
        sourceButton.image = TemplateSymbolImage.make("doc.text", accessibilityDescription: nil)
        sourceButton.imagePosition = .imageLeading
        sourceButton.contentTintColor = theme.vocabularyAccentColor
        sourceButton.font = AppFont.semibold(ofSize: 14)
        sourceButton.alignment = .left
        sourceButton.lineBreakMode = .byTruncatingMiddle
        sourceButton.toolTip = AppText.localized(
            "打开 \(occurrence.documentURL.path) · \(occurrence.location)",
            "Open \(occurrence.documentURL.path) · \(occurrence.location)"
        )
        sourceButton.setAccessibilityLabel(AppText.localized(
            "在 \(occurrence.documentTitle) 中打开 \(occurrence.location)",
            "Open \(occurrence.location) in \(occurrence.documentTitle)"
        ))
        sourceButton.translatesAutoresizingMaskIntoConstraints = false

        let location = NSTextField(labelWithString: occurrence.location)
        location.font = AppFont.semibold(ofSize: 12)
        location.textColor = theme.vocabularySecondaryTextColor
        location.alignment = .right
        location.translatesAutoresizingMaskIntoConstraints = false

        let contextText = occurrence.context.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = NSTextField(wrappingLabelWithString: contextText.isEmpty
            ? AppText.localized("没有可用的上下文", "No context available")
            : contextText)
        if !contextText.isEmpty {
            context.attributedStringValue = owner?.vocabularyExampleAttributedString(
                contextText,
                word: word,
                fontSize: 14,
                textColor: theme.vocabularyBodyTextColor
            ) ?? NSAttributedString(
                string: contextText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: theme.vocabularyBodyTextColor
                ]
            )
        }
        context.maximumNumberOfLines = 0
        context.allowsEditingTextAttributes = true
        context.isSelectable = true
        // Wrap instead of demanding width. Without this an unbroken run of
        // context text raises the card's required width, which propagates out
        // to the stack and forces the whole window wider than the screen.
        context.lineBreakMode = .byWordWrapping
        context.cell?.wraps = true
        context.cell?.isScrollable = false
        context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(sourceButton)
        card.addSubview(location)
        card.addSubview(context)
        NSLayoutConstraint.activate([
            sourceButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            sourceButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            sourceButton.trailingAnchor.constraint(lessThanOrEqualTo: location.leadingAnchor, constant: -10),
            sourceButton.heightAnchor.constraint(equalToConstant: 24),
            location.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            location.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
            location.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
            context.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            context.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            context.topAnchor.constraint(equalTo: sourceButton.bottomAnchor, constant: 8),
            context.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
        return card
    }
}
