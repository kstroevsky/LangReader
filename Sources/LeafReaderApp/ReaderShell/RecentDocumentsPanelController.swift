import Cocoa
import SwiftUI
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import LeafReaderCore

final class RecentDocumentsPanelController: NSObject {
    struct ShelfRemovalOptions {
        let clearVectorCache: Bool
        let clearWordRecords: Bool
        let clearAIData: Bool
    }

    weak var parentWindow: NSWindow?
    var panel: NSWindow?
    var onOpen: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onRemoveItem: ((String, ShelfRemovalOptions) -> Void)?
    var onClearVectorCache: ((String) -> Void)?
    var onClearWordRecords: ((String) -> Void)?
    var onClearAIData: ((String) -> Void)?
    var onImport: (([URL]) -> Void)?
    var onClose: (() -> Void)?
    let model = ShelfModel()
    var pendingOpenPath: String?
    var isClosing = false
    var appActivationObserver: NSObjectProtocol?

    let panelSize = NSSize(width: 940, height: 480)

    deinit {
        removeAppActivationObserver()
    }

    func show(
        items: [RecentDocumentItem],
        attachedTo window: NSWindow?,
        focusPath: String? = nil,
        onOpen: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onRemoveItem: @escaping (String, ShelfRemovalOptions) -> Void,
        onClearVectorCache: @escaping (String) -> Void,
        onClearWordRecords: @escaping (String) -> Void,
        onClearAIData: @escaping (String) -> Void,
        onImport: @escaping ([URL]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onClear = onClear
        self.onRemoveItem = onRemoveItem
        self.onClearVectorCache = onClearVectorCache
        self.onClearWordRecords = onClearWordRecords
        self.onClearAIData = onClearAIData
        self.onImport = onImport
        self.onClose = onClose
        self.parentWindow = window

        let theme = ReaderTheme.selected
        model.update(items: items, focusPath: focusPath)
        model.theme = theme
        wireModel()

        let panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        // The drop view stays AppKit: dragging documents onto the shelf already
        // works through it, and it is the small bridge component the migration
        // is meant to keep rather than re-implement.
        let content = RecentDocumentsDropContentView()
        content.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }
        content.wantsLayer = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = shelfBorderColor(for: theme).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = theme == .dark ? 0.42 : 0.24
        content.layer?.shadowRadius = 32
        content.layer?.shadowOffset = CGSize(width: 0, height: -12)
        panel.contentView = content

        let hosting = NSHostingView(rootView: ShelfView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Clipped separately from the drop view, whose shadow must not be
        // masked away.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        content.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: content.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        self.panel = panel
        installAppActivationObserver()
        showPanel(panel, attachedTo: window)
    }

    /// Routes the shelf's actions. The destructive ones confirm first — the
    /// view only reports intent.
    private func wireModel() {
        model.onOpen = { [weak self] path in
            self?.pendingOpenPath = path
            self?.close()
        }
        model.onReveal = { path in
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        model.onRemove = { [weak self] path in
            guard let self, let options = self.confirmShelfRemoval() else { return }
            self.onRemoveItem?(path, options)
            self.model.removeLocally(path: path)
        }
        model.onClearVectorCache = { [weak self] path in
            guard let self, self.confirmShelfAction(
                title: AppText.localized("清除本书 AI 分析缓存？", "Clear AI Analysis Cache for This Book?"),
                message: AppText.localized("这会删除本书的向量分析缓存。之后使用文档问答时会重新生成。", "This deletes this book's vector analysis cache. It will be rebuilt when document Q&A is used."),
                confirmTitle: AppText.localized("清除", "Clear")
            ) else { return }
            self.onClearVectorCache?(path)
        }
        model.onClearWordRecords = { [weak self] path in
            guard let self, self.confirmShelfAction(
                title: AppText.localized("清除本书单词记录？", "Clear Word Records for This Book?"),
                message: AppText.localized("这会删除本书已保存的单词、解释和高亮记录。", "This deletes saved words, explanations, and highlights for this book."),
                confirmTitle: AppText.localized("清除", "Clear")
            ) else { return }
            self.onClearWordRecords?(path)
        }
        model.onClearAIData = { [weak self] path in
            guard let self, self.confirmShelfAction(
                title: AppText.localized("清除本书 AI 数据？", "Clear AI Data for This Book?"),
                message: AppText.localized("这会删除本书已保存的 AI 对话、来源标注和单词学习记录。", "This deletes saved AI conversations, source marks, and word learning records for this book."),
                confirmTitle: AppText.localized("清除", "Clear")
            ) else { return }
            self.onClearAIData?(path)
        }
        model.onAdd = { [weak self] in
            self?.openDocumentFromShelf(nil)
        }
        model.onClearAll = { [weak self] in
            self?.clearRecentDocuments(nil)
        }
        model.onClose = { [weak self] in
            self?.closePanel(nil)
        }
    }
}
