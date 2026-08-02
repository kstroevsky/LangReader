import Foundation

/// A declarative description of one control in the reader's bottom bar.
///
/// The counterpart to `ReaderToolbarItem`, which already describes the top
/// toolbar this way. The bottom bar's buttons were instead built by hand,
/// each repeating the same four lines with a different title and symbol, so its
/// order lived only in the order of those statements and could not be inspected
/// or tested.
///
/// Carries no AppKit references: the controller turns each descriptor into a
/// real button and supplies the action, which keeps the composition rules
/// testable.
package struct ReaderBottomBarItem: Equatable {
    package enum Identifier: String, Equatable, CaseIterable {
        case settings
        case shelf
        case words
        case notes
        case review
        case toc
        case embeddingPause
        case embeddingCancel

        /// A stable accessibility identifier for the control's real view.
        ///
        /// Deliberately not localised and not the button title: the smoke test
        /// and any assistive tech should find the same control whatever the
        /// interface language, and this identifier will carry over unchanged
        /// when the bar is rebuilt in SwiftUI.
        package var accessibilityIdentifier: String { "bottomBar.\(rawValue)" }
    }

    /// Which cluster of the bar the control belongs to.
    package enum Cluster: Equatable {
        /// The gear, pinned to the leading edge on its own.
        case settings
        /// The panel-opening buttons, in order after the gear.
        case panels
        /// The page-navigation group, centred as a unit.
        case navigation
        /// Controls for a running AI analysis, hidden unless one is active.
        case embedding
    }

    package let id: Identifier
    package let cluster: Cluster
    /// Whether the button draws its symbol beside the title. The navigation
    /// group does not: those buttons sit together and read as a unit, so a
    /// symbol on each adds noise rather than meaning.
    package let showsLeadingSymbol: Bool

    /// True for controls that are only shown while an AI analysis is running.
    package var isTransient: Bool { cluster == .embedding }
}

package enum ReaderBottomBarLayout {
    /// The whole specification of the bar. Reordering is reordering this array;
    /// adding a button is appending one entry.
    package static let items: [ReaderBottomBarItem] = [
        ReaderBottomBarItem(id: .settings, cluster: .settings, showsLeadingSymbol: false),
        // Order matches the on-screen bar: Shelf, Words, Review, Notes. The
        // named layout constraints put Review before Notes, so the descriptor
        // has to agree — once the SwiftUI bar renders from this array, the array
        // *is* the order.
        ReaderBottomBarItem(id: .shelf, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .words, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .review, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .notes, cluster: .panels, showsLeadingSymbol: true),
        ReaderBottomBarItem(id: .toc, cluster: .navigation, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .embeddingPause, cluster: .embedding, showsLeadingSymbol: false),
        ReaderBottomBarItem(id: .embeddingCancel, cluster: .embedding, showsLeadingSymbol: false)
    ]

    package static func items(in cluster: ReaderBottomBarItem.Cluster) -> [ReaderBottomBarItem] {
        items.filter { $0.cluster == cluster }
    }
}
