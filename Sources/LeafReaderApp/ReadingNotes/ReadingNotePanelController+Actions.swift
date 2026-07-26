import Cocoa

extension ReadingNotePanelController {
    func save() {
        onSave(editorModel.commitEdits(markdown: markdownFromEditor()))
    }

    /// Applies a favourite change made outside this panel. Routed through here
    /// rather than written onto the controller so the editor's own note is the
    /// one that changes — and so the save carries the editor's live text instead
    /// of the list's stale copy.
    func setFavorite(_ isFavorite: Bool) {
        editorModel.setFavorite(isFavorite)
        save()
        refreshStatusLabel()
    }

    func commitEditorChange() {
        save()
        refreshEditorDerivedState()
    }

    func refreshEditorDerivedState() {
        updateWordCount()
        refreshAIToolbar()
    }

    @objc func saveTapped(_ sender: NSButton) {
        autoSaveTask.cancel()
        save()
        editorModel.statusSaved()
        refreshStatusLabel()
    }

    func updateWordCount() {
        editorModel.syncText(textView.string)
        wordCountLabel.stringValue = editorModel.wordCountText
    }

    /// Mirrors the model's status line into the AppKit label. The text view and
    /// its chrome are still AppKit, so the model is rendered rather than bound.
    func refreshStatusLabel() {
        statusLabel.stringValue = editorModel.statusMessage
    }

    func noteLocationText() -> String { editorModel.locationText }

    func createdAtText() -> String { editorModel.createdAtText }

    func scheduleAutoSave() {
        autoSaveTask.schedule { [weak self] in
            self?.save()
        }
    }

    @objc func showNotesTapped(_ sender: NSButton) {
        closeAfterExplicitSave()
        onShowNotes()
    }

    @objc func moreTapped(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(menuItem(
            title: note.isFavorite
                ? AppText.localized("取消收藏", "Remove Favorite")
                : AppText.localized("收藏并置顶", "Favorite and Pin"),
            action: #selector(toggleFavoriteTapped(_:))
        ))
        menu.addItem(.separator())
        let templateMenu = NSMenu()
        ReadingNoteTemplate.allCases.forEach { template in
            let item = menuItem(title: template.title, action: #selector(templateMenuItemTapped(_:)))
            item.representedObject = template.rawValue
            templateMenu.addItem(item)
        }
        let templateItem = NSMenuItem(title: AppText.localized("套用模板", "Apply Template"), action: nil, keyEquivalent: "")
        templateItem.submenu = templateMenu
        menu.addItem(templateItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: AppText.localized("导出当前笔记...", "Export This Note..."), action: #selector(exportCurrentNoteTapped(_:))))
        menu.addItem(menuItem(title: AppText.localized("复制 Markdown", "Copy Markdown"), action: #selector(copyMarkdownTapped(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: AppText.localized("删除笔记", "Delete Note"), action: #selector(deleteCurrentNoteTapped(_:))))
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func exportCurrentNoteTapped(_ sender: NSMenuItem) {
        save()
        onExportNote(note)
    }

    @objc func copyMarkdownTapped(_ sender: NSMenuItem) {
        save()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.markdown, forType: .string)
        editorModel.statusMarkdownCopied()
        refreshStatusLabel()
    }

    @objc func toggleFavoriteTapped(_ sender: NSMenuItem) {
        setFavorite(!note.isFavorite)
    }

    @objc func templateMenuItemTapped(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let template = ReadingNoteTemplate(rawValue: raw) else { return }
        applyTemplate(template)
    }

    @objc func deleteCurrentNoteTapped(_ sender: NSMenuItem) {
        onDeleteNote(note)
    }

    private func closeAfterExplicitSave() {
        save()
        editorModel.savesOnClose = false
        close()
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
