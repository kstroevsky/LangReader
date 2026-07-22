import Foundation

/// A declarative description of one control in the reader's bottom bar.
///
/// The counterpart to `ReaderToolbarItem`, which already describes the top
/// toolbar this way. The bottom bar's nine buttons were instead built by hand,
/// each repeating the same four lines with a different title and symbol, so its
/// order lived only in the order of those statements and could not be inspected
/// or tested.
///
/// Carries no AppKit references: the controller turns each descriptor into a
/// real button and supplies the action, which keeps the composition rules
/// testable.
struct ReaderBottomBarItem: Equatable {
    enum Identifier: String, Equatable, CaseIterable {
        case settings
        case shelf
        case words
        case notes
        case review
        case toc
        case cover
        case previousPage
        case nextPage
        case farthestPosition
        case embeddingPause
        case embeddingCancel
    }

    /// Which cluster of the bar the control belongs to.
    enum Cluster: Equatable {
        /// The gear, pinned to the leading edge on its own.
        case settings
        /// The panel-opening buttons, in order after the gear.
        case panels
        /// The page-navigation group, centred as a unit.
        case navigation
        /// Controls for a running AI analysis, hidden unless one is active.
        case embedding
    }

    let id: Identifier
    let cluster: Cluster
    /// Whether the button draws its symbol beside the title. The navigation
    /// group does not: those buttons sit together and read as a unit, so a
    /// symbol on each adds noise rather than meaning.
    let showsLeadingSymbol: Bool

    /// True for controls that are only shown while an AI analysis is running.
    var isTransient: Bool { cluster == .embedding }
}

enum ReaderBottomBarLayout {
    /// The whole specification of the bar. Reordering is reordering this array;
    /// adding a button is appending one entry.
    static let items: [ReaderBottomBarItem] = [
        ReaderBottomBarItem(id: .settings, cluster: .settings, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .shelf, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .words, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .notes, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .review, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .toc, cluster: .navigation, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .cover, cluster: .navigation, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .previousPage, cluster: .navigation, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .nextPage, cluster: .navigation, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .farthestPosition, cluster: .navigation, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .embeddingPause, cluster: .embedding, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .embeddingCancel, cluster: .embedding, showsLeadingSymbol: false)
    ]

    static func items(in cluster: ReaderBottomBarItem.Cluster) -> [ReaderBottomBarItem] {
        items.filter { $0.cluster == cluster }
    }

    /// What the bar shows at rest — everything except the AI-analysis controls,
    /// which appear only while an analysis is running.
    static var restingItems: [ReaderBottomBarItem] {
        items.filter { !$0.isTransient }
    }
}
