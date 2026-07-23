import Cocoa
import CryptoKit
import PDFKit

/// Renders and caches the cover thumbnails shown on the shelf.
///
/// This was inlined in the shelf's AppKit controller, where it pushed images
/// straight into an `NSImageView`. Nothing that renders differently — SwiftUI,
/// or any future shelf — could reuse it, and the caches were static properties
/// on a view controller. It is a service, so it lives as one.
///
/// Three tiers, cheapest first: an in-memory cache, a PNG on disk, then an
/// actual render of the document's first page. Rendering is the slow one, which
/// is why a placeholder is shown immediately and replaced when the real cover
/// arrives.
@Observable
final class ShelfCoverLoader {
    /// Shared because the caches should outlive any one shelf window — reopening
    /// the shelf should not re-render every cover.
    static let shared = ShelfCoverLoader()

    static let coverSize = NSSize(width: 120, height: 205)

    /// Rendered covers by cache key. Observed by the shelf, so an arriving cover
    /// swaps itself in.
    private(set) var covers: [String: PlatformImage] = [:]

    @ObservationIgnored private var placeholders: [String: NSImage] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Keyed by content, not just path: a document edited in place must not keep
    /// showing its old cover. The theme is in the key because the placeholder is
    /// drawn light or dark.
    func cacheKey(for item: RecentDocumentItem) -> String {
        let url = URL(fileURLWithPath: item.path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let digest = SHA256.hash(
            data: Data("\(item.path)#\(item.kind)#\(ReaderTheme.selected.rawValue)#\(modified)#\(fileSize)".utf8)
        )
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func cachedCover(for item: RecentDocumentItem) -> PlatformImage? {
        covers[cacheKey(for: item)]
    }

    /// A drawn stand-in used until the real cover renders. Cached because the
    /// shelf rebuilds its cards on every open and redrawing text into a bitmap
    /// for each one is visible work.
    func placeholder(title: String, kind: String, isDark: Bool) -> PlatformImage {
        let key = "\(ReaderTheme.selected.rawValue)#\(kind)#\(title)#\(isDark)"
        if let cached = placeholders[key] { return cached }
        let image = drawPlaceholder(title: title, kind: kind, isDark: isDark)
        placeholders[key] = image
        return image
    }

    /// Loads the cover if it is not already known. Safe to call repeatedly —
    /// duplicate requests for the same key are dropped, so a shelf that rebuilds
    /// its cards does not queue the same render several times.
    func loadCover(for item: RecentDocumentItem) {
        let key = cacheKey(for: item)
        guard covers[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)

        let path = item.path
        let kind = item.kind
        queue.addOperation { [weak self] in
            guard let self else { return }
            let image = self.loadFromDisk(cacheKey: key) ?? self.render(path: path, kind: kind)
            DispatchQueue.main.async {
                self.inFlight.remove(key)
                guard let image else { return }
                self.covers[key] = image
                self.saveToDisk(image, cacheKey: key)
            }
        }
    }

    /// Pauses cover rendering.
    ///
    /// Used while the open panel is up: rendering PDF pages competes with the
    /// file dialog, which made it slow to appear.
    func setPaused(_ paused: Bool) {
        queue.isSuspended = paused
    }

    // MARK: Rendering

    private func render(path: String, kind: String) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        switch kind {
        case "EPUB":
            guard let data = try? WebDocumentLoader.coverImageData(forEPUB: url),
                  let image = NSImage(data: data) else { return nil }
            image.size = Self.coverSize
            image.cacheMode = .always
            return image
        case "PDF":
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let renderScale = max(2, min(3, scale))
            let targetSize = NSSize(
                width: Self.coverSize.width * renderScale,
                height: Self.coverSize.height * renderScale
            )
            let image = page.thumbnail(of: targetSize, for: .cropBox)
            image.size = Self.coverSize
            image.cacheMode = .always
            return image
        default:
            // DOCX and anything else have no renderable first page; the
            // placeholder is the final answer rather than a temporary one.
            return nil
        }
    }

    // MARK: Disk cache

    private func diskURL(cacheKey: String) -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ShelfCovers", isDirectory: true)
            .appendingPathComponent("\(cacheKey).png")
    }

    private func loadFromDisk(cacheKey: String) -> NSImage? {
        guard let url = diskURL(cacheKey: cacheKey),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let image = NSImage(contentsOf: url) {
            image.size = Self.coverSize
            return image
        }
        log("Failed to read cached cover at \(url.path)", cacheKey: cacheKey)
        return nil
    }

    private func saveToDisk(_ image: NSImage, cacheKey: String) {
        guard let url = diskURL(cacheKey: cacheKey) else {
            log("No cover cache URL available", cacheKey: cacheKey)
            return
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            log("Failed to encode cover as PNG", cacheKey: cacheKey)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            log("Failed to write cover cache at \(url.path)", cacheKey: cacheKey, error: error)
        }
    }

    private func log(_ message: String, cacheKey: String, error: Error? = nil) {
        if let error {
            NSLog("LeafReader cover cache: %@ (cacheKey=%@, error=%@)", message, cacheKey, error.localizedDescription)
        } else {
            NSLog("LeafReader cover cache: %@ (cacheKey=%@)", message, cacheKey)
        }
    }

    private func drawPlaceholder(title: String, kind: String, isDark: Bool) -> NSImage {
        let coverSize = Self.coverSize
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderScale = max(2, min(3, scale))
        let renderSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
        let image = NSImage(size: coverSize)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(renderSize.width),
            pixelsHigh: Int(renderSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }

        bitmap.size = coverSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(origin: .zero, size: coverSize)
        (isDark ? NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1) : NSColor.white).setFill()
        rect.fill()
        (isDark
            ? NSColor(red: 0.28, green: 0.32, blue: 0.39, alpha: 1)
            : NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        ).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13),
            .foregroundColor: isDark ? NSColor.white : NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let kindAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 9),
            .foregroundColor: isDark
                ? NSColor(red: 0.70, green: 0.76, blue: 0.84, alpha: 1)
                : NSColor(red: 0.35, green: 0.39, blue: 0.48, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let trimmedTitle = title.count > 34 ? String(title.prefix(34)) : title
        NSString(string: trimmedTitle).draw(
            in: NSRect(x: 14, y: coverSize.height * 0.48, width: coverSize.width - 28, height: 54),
            withAttributes: titleAttributes
        )
        NSString(string: ShelfCardPresenter.documentKindText(kind)).draw(
            in: NSRect(x: 12, y: 18, width: coverSize.width - 24, height: 18),
            withAttributes: kindAttributes
        )
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(bitmap)
        return image
    }
}
