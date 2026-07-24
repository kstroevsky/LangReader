import Cocoa

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class SideHandleButton: NSButton {
    static let handleWidth: CGFloat = 19
    static let handleHeight: CGFloat = 67

    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    var collapsedStyle = true {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        handleFillColor.setFill()
        path.fill()

        let symbol = collapsedStyle ? "‹" : "›"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let size = symbol.size(withAttributes: attrs)
        symbol.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 + 1), withAttributes: attrs)
    }

    private var handleFillColor: NSColor {
        theme.sideHandleFillColor(isHighlighted: isHighlighted)
    }
}

final class CapsuleChromeButton: NSButton {
    var leadingSymbolName: String? {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    var leadingSymbolDescription: String?

    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    var isDark = false {
        didSet {
            theme = isDark ? .dark : .original
            needsDisplay = true
        }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13)
        ]
        let textWidth = title.size(withAttributes: attrs).width
        let symbolWidth: CGFloat = leadingSymbolName == nil ? 0 : 20
        return NSSize(width: max(64, ceil(textWidth + symbolWidth) + 28), height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)

        let fillColor: NSColor
        let strokeColor: NSColor
        let textColor: NSColor
        switch theme {
        case .dark:
            fillColor = NSColor(red: isHighlighted ? 0.15 : 0.09, green: isHighlighted ? 0.18 : 0.11, blue: isHighlighted ? 0.23 : 0.15, alpha: 1)
            strokeColor = NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1) : NSColor(red: 0.45, green: 0.49, blue: 0.55, alpha: 1)
        case .eyeCare:
            fillColor = NSColor(red: isHighlighted ? 0.82 : 0.88, green: isHighlighted ? 0.76 : 0.82, blue: isHighlighted ? 0.58 : 0.66, alpha: 1)
            strokeColor = NSColor(red: 0.66, green: 0.60, blue: 0.43, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1) : NSColor(red: 0.54, green: 0.48, blue: 0.33, alpha: 1)
        case .original:
            fillColor = NSColor(red: isHighlighted ? 0.92 : 1.0, green: isHighlighted ? 0.94 : 1.0, blue: isHighlighted ? 0.97 : 1.0, alpha: 1)
            strokeColor = NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            textColor = isEnabled ? NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1) : NSColor(red: 0.64, green: 0.67, blue: 0.72, alpha: 1)
        }

        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textRect = bounds.insetBy(dx: 8, dy: 0)
        let titleSize = title.size(withAttributes: attrs)
        let hasLeadingSymbol = leadingSymbolName != nil
        let symbolSize = NSSize(width: 14, height: 14)
        let symbolSpacing: CGFloat = hasLeadingSymbol ? 6 : 0
        let contentWidth = titleSize.width + (hasLeadingSymbol ? symbolSize.width + symbolSpacing : 0)
        var contentX = max(textRect.minX, bounds.midX - contentWidth / 2)
        if let leadingSymbolName,
           let image = NSImage(systemSymbolName: leadingSymbolName, accessibilityDescription: leadingSymbolDescription)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))?
            .tintedChrome(with: textColor) {
            let iconRect = NSRect(
                x: contentX,
                y: max(0, (bounds.height - symbolSize.height) / 2),
                width: symbolSize.width,
                height: symbolSize.height
            )
            image.draw(in: iconRect)
            contentX += symbolSize.width + symbolSpacing
        }
        let drawRect = NSRect(
            x: contentX,
            y: max(0, (bounds.height - titleSize.height) / 2),
            width: max(0, min(titleSize.width + 1, textRect.maxX - contentX)),
            height: titleSize.height
        )
        (title as NSString).draw(in: drawRect, withAttributes: attrs)
    }
}

private extension NSImage {
    func tintedChrome(with color: NSColor) -> NSImage {
        let image = copy() as? NSImage ?? self
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

final class SearchUnderlineButton: NSButton {
    var theme: ReaderTheme = .original {
        didSet { needsDisplay = true }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        searchUnderlineColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        let underlineY = bounds.isEmpty ? 0 : bounds.height - 4
        path.move(to: NSPoint(x: 0, y: underlineY))
        path.line(to: NSPoint(x: bounds.width, y: underlineY))
        path.stroke()
    }

    private var searchUnderlineColor: NSColor {
        theme.searchUnderlineColor(isHighlighted: isHighlighted)
    }
}

final class ResizeHandleView: NSView {
    var onDragDeltaX: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var theme: ReaderTheme = .selected {
        didSet { layer?.backgroundColor = theme.resizeHandleColor.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = theme.resizeHandleColor.cgColor
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        onDragDeltaX?(event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }
}

final class ClippingView: NSView {
    var onDroppedDocumentURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = ReaderTheme.selected.chromeBackgroundColor.cgColor
        ReaderFileDrop.register(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
}

final class PassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
