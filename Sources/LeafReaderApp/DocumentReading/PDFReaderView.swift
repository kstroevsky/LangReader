import Cocoa
import PDFKit
import LeafReaderCore

final class ReaderPDFView: PDFView {
    var onDroppedDocumentURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ReaderFileDrop.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        ReaderFileDrop.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ReaderFileDrop.perform(sender) { [weak self] urls in
            self?.onDroppedDocumentURLs?(urls)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let sourceMenu = super.menu(for: event) ?? fallbackContextMenu()
        return sanitizedContextMenu(from: sourceMenu)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let selection = copiedCurrentSelection(),
              (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            super.rightMouseDown(with: event)
            return
        }

        setCurrentSelection(selection, animate: false)
        guard let menu = menu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        if currentSelection?.string?.isEmpty != false {
            setCurrentSelection(selection, animate: false)
        }
    }

    private func copiedCurrentSelection() -> PDFSelection? {
        currentSelection?.copy() as? PDFSelection
    }

    private func fallbackContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        return menu
    }

    private func sanitizedContextMenu(from sourceMenu: NSMenu) -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false

        let groups = [resizeContextMenuTitles, pageTurnContextMenuTitles]
        for allowedGroup in groups {
            var didAddGroupItem = false
            for item in sourceMenu.items {
                guard !item.isSeparatorItem,
                      allowedGroup.contains(normalizedContextMenuTitle(item.title)) else {
                    continue
                }
                let copy = NSMenuItem(title: localizedAllowedContextMenuTitle(item.title), action: item.action, keyEquivalent: "")
                copy.target = item.target
                copy.state = item.state
                copy.isEnabled = item.isEnabled
                copy.tag = item.tag
                copy.representedObject = item.representedObject
                copy.image = item.image
                menu.addItem(copy)
                didAddGroupItem = true
            }
            if didAddGroupItem {
                menu.addItem(.separator())
            }
        }
        trimContextMenuSeparators(menu)
        return menu
    }

    private func normalizedContextMenuTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "...")
            .lowercased()
    }

    private var resizeContextMenuTitles: Set<String> {
        Set([
            "automatically resize", "自动调整大小",
            "zoom in", "放大",
            "zoom out", "缩小",
            "actual size", "实际大小"
        ])
    }

    private var pageTurnContextMenuTitles: Set<String> {
        Set([
            "next page", "下一页",
            "previous page", "上一页"
        ])
    }

    private func trimContextMenuSeparators(_ menu: NSMenu) {
        while menu.items.first?.isSeparatorItem == true {
            menu.removeItem(at: 0)
        }
        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }
        var index = menu.items.count - 1
        while index > 0 {
            if menu.items[index].isSeparatorItem, menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            }
            index -= 1
        }
    }

    private func localizedAllowedContextMenuTitle(_ title: String) -> String {
        switch normalizedContextMenuTitle(title) {
        case "automatically resize", "自动调整大小":
            return localizedMenuTitle(zh: "自动调整大小", en: "Automatically Resize")
        case "zoom in", "放大":
            return localizedMenuTitle(zh: "放大", en: "Zoom In")
        case "zoom out", "缩小":
            return localizedMenuTitle(zh: "缩小", en: "Zoom Out")
        case "actual size", "实际大小":
            return localizedMenuTitle(zh: "实际大小", en: "Actual Size")
        case "next page", "下一页":
            return localizedMenuTitle(zh: "下一页", en: "Next Page")
        case "previous page", "上一页":
            return localizedMenuTitle(zh: "上一页", en: "Previous Page")
        default:
            return title
        }
    }

    private func localizedMenuTitle(zh: String, en: String) -> String {
        AppText.localized(zh, en)
    }
}
