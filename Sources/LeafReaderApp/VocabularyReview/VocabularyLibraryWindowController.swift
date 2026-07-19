import Cocoa

final class VocabularyLibrarySourceButton: NSButton {
    var occurrence: VocabularyLibraryOccurrence?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
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
    private let detailStack = NSStackView()
    private(set) var window: NSWindow?
    private var records: [VocabularyLibraryRecord] = []
    private var filteredRecords: [VocabularyLibraryRecord] = []

    init(owner: ReaderWindowController) {
        self.owner = owner
        super.init()
    }

    deinit {
        reloadTask.cancel()
    }

    func show(records: [VocabularyLibraryRecord]) {
        if window == nil {
            buildWindow()
        }
        update(records: records)
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

    func close() {
        window?.close()
    }

    func scheduleReload() {
        reloadTask.schedule { [weak self] in
            guard let self, self.window?.isVisible == true, let owner = self.owner else { return }
            self.update(records: owner.makeVocabularyLibraryRecords())
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
        panel.minSize = NSSize(width: 960, height: 620)
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

    private func update(records: [VocabularyLibraryRecord]) {
        let selectedID = selectedRecord?.id
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
            let haystack = ([record.word, record.answer, record.dictionaryTags ?? ""] + record.occurrences.flatMap {
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
        refreshDetail()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilters(preferredSelectionID: selectedRecord?.id)
    }

    @objc private func filterChanged(_ sender: Any?) {
        applyFilters(preferredSelectionID: selectedRecord?.id)
    }

    @objc private func refreshTapped(_ sender: Any?) {
        guard let owner else { return }
        update(records: owner.makeVocabularyLibraryRecords())
    }

    @objc private func copyWord(_ sender: NSButton) {
        guard let word = selectedRecord?.word else { return }
        owner?.copyTextToClipboard(word)
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
        wordRow.addArrangedSubview(wordLabel)
        wordRow.addArrangedSubview(copyButton)
        detailStack.addArrangedSubview(wordRow)
        wordRow.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true

        let metadataParts = [
            record.dictionaryTags,
            record.dictionaryFrequency.map { AppText.localized("词频 #\($0)", "Frequency #\($0)") },
            AppText.localized("\(occurrences.count) 个出处", "\(occurrences.count) occurrences")
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let metadata = NSTextField(labelWithString: metadataParts.joined(separator: "  ·  "))
        metadata.font = AppFont.semibold(ofSize: 12)
        metadata.textColor = theme.vocabularySecondaryTextColor
        detailStack.addArrangedSubview(metadata)

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
            answer.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true
        }

        let separator = NSBox()
        separator.boxType = .separator
        detailStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -12).isActive = true

        let occurrencesTitle = NSTextField(labelWithString: AppText.localized("出处与上下文", "Occurrences & context"))
        occurrencesTitle.font = AppFont.semibold(ofSize: 17)
        occurrencesTitle.textColor = theme.vocabularyPrimaryTextColor
        detailStack.addArrangedSubview(occurrencesTitle)

        for occurrence in occurrences {
            let view = occurrenceView(occurrence, theme: theme)
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

    private func occurrenceView(_ occurrence: VocabularyLibraryOccurrence, theme: ReaderTheme) -> NSView {
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
        context.font = NSFont.systemFont(ofSize: 14)
        context.textColor = theme.vocabularyBodyTextColor
        context.maximumNumberOfLines = 0
        context.isSelectable = true
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
