import Cocoa
import SwiftUI
import LeafReaderCore

/// The window shell around the Reading Notes list.
///
/// The list itself is SwiftUI (`ReadingNotesListView`); what stays here is the
/// part SwiftUI does not own — a borderless panel, where it sits relative to
/// the reader window, and keeping the model's theme in step with the app's.
final class ReadingNotesPanelController: NSObject {
    private enum Metrics {
        static let panelSize = NSSize(width: 560, height: 420)
        static let cornerRadius: CGFloat = 16
        static let screenInset: CGFloat = 12
    }

    var onOpenNote: ((ReadingNote) -> Void)? {
        didSet { model.onOpenNote = onOpenNote }
    }
    var onDeleteNote: ((ReadingNote) -> Void)? {
        didSet { model.onDeleteNote = onDeleteNote }
    }
    var onToggleFavorite: ((ReadingNote) -> Void)? {
        didSet { model.onToggleFavorite = onToggleFavorite }
    }
    var onExport: (() -> Void)? {
        didSet { model.onExport = onExport }
    }
    var onClose: (() -> Void)?

    private(set) var panel: NSWindow?
    private let model = ReadingNotesListModel()

    override init() {
        super.init()
        model.onClose = { [weak self] in
            guard let self else { return }
            self.close(attachedTo: self.panel?.parent)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(readerThemeDidChange(_:)),
            name: .readerThemeDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(notes: [ReadingNote], parent: NSWindow?) {
        model.update(notes: notes)
        model.theme = ReaderTheme.selected
        if panel == nil {
            panel = buildPanel()
        }
        guard let panel else { return }
        panel.setContentSize(Metrics.panelSize)
        applyAppearance(ReaderTheme.selected)
        center(panel, relativeTo: parent)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func update(notes: [ReadingNote]) {
        model.update(notes: notes)
    }

    func refreshTheme() {
        model.theme = ReaderTheme.selected
        applyAppearance(ReaderTheme.selected)
    }

    func close(attachedTo parent: NSWindow?) {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
        onClose?()
    }

    private func buildPanel() -> NSWindow {
        let panel = ReadingNotesPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        // The hosting view is clipped to the panel's rounded corners; the panel
        // is borderless, so nothing else would round them.
        let hosting = NSHostingView(rootView: ReadingNotesListView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Metrics.cornerRadius
        hosting.layer?.borderWidth = 1
        hosting.layer?.masksToBounds = true
        hosting.frame = NSRect(origin: .zero, size: Metrics.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func center(_ panel: NSWindow, relativeTo parent: NSWindow?) {
        guard let parent else {
            panel.center()
            return
        }
        let parentFrame = parent.frame
        let origin = NSPoint(
            x: parentFrame.midX - panel.frame.width / 2,
            y: parentFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(
            clampedOrigin(origin, panelSize: panel.frame.size, visibleFrame: parent.screen?.visibleFrame)
        )
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect?) -> NSPoint {
        guard let visibleFrame else { return origin }
        let inset = Metrics.screenInset
        let minX = visibleFrame.minX + inset
        let maxX = visibleFrame.maxX - panelSize.width - inset
        let minY = visibleFrame.minY + inset
        let maxY = visibleFrame.maxY - panelSize.height - inset
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func applyAppearance(_ theme: ReaderTheme) {
        guard let panel else { return }
        panel.appearance = theme == .dark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
        panel.contentView?.layer?.borderColor = ReadingNoteTheme.panelBorder(theme).cgColor
    }

    @objc private func readerThemeDidChange(_ notification: Notification) {
        refreshTheme()
    }
}

private final class ReadingNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
