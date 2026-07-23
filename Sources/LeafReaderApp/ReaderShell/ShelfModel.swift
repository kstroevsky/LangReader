import Foundation
import Observation

/// State behind the shelf.
///
/// The destructive actions deliberately do not act here. Each one routes back
/// out to the panel, which asks for confirmation with an `NSAlert` before
/// anything is deleted — a shelf that could wipe a book's words the moment a
/// menu item was picked would be one mis-click from data loss.
@Observable
final class ShelfModel {
    private(set) var items: [RecentDocumentItem] = []
    /// A document to scroll into view. Set when the shelf is opened right after
    /// an import, so the file just added is visible rather than off the end of
    /// a long shelf.
    var focusPath: String?
    var theme: ReaderTheme = ReaderTheme.selected

    @ObservationIgnored var onOpen: ((String) -> Void)?
    @ObservationIgnored var onReveal: ((String) -> Void)?
    @ObservationIgnored var onRemove: ((String) -> Void)?
    @ObservationIgnored var onClearVectorCache: ((String) -> Void)?
    @ObservationIgnored var onClearWordRecords: ((String) -> Void)?
    @ObservationIgnored var onClearAIData: ((String) -> Void)?
    @ObservationIgnored var onAdd: (() -> Void)?
    @ObservationIgnored var onClearAll: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?

    let covers = ShelfCoverLoader.shared

    var isEmpty: Bool { items.isEmpty }

    func update(items: [RecentDocumentItem], focusPath: String? = nil) {
        self.items = items
        self.focusPath = focusPath
    }

    /// Drops a card without waiting for the shelf to be rebuilt, so the row
    /// disappears the moment the removal is confirmed.
    func removeLocally(path: String) {
        items.removeAll { $0.path == path }
    }
}
