import CoreGraphics
import Foundation

/// A declarative description of one reader toolbar control.
///
/// Toolbar controls used to be created, positioned and shown/hidden in three
/// different files, so adding one meant editing all of them and inventing new
/// layout constants. Describing a control as data instead means the arrays in
/// `ReaderToolbarLayout` are the whole specification: reordering is reordering
/// the array, and adding a control is appending one entry.
///
/// This type carries no AppKit references so the composition rules stay
/// testable; the controller turns each descriptor into a real view.
struct ReaderToolbarItem: Equatable {
    /// Identifies the control and the view the controller builds for it.
    enum Identifier: String, Equatable, CaseIterable {
        case cover
        case title
        case relatedFormsToggle
        case readAloud
        case readAloudStop
        case pageLayout
        case crop
    }

    /// Which cluster of the toolbar the control belongs to.
    enum Placement: Equatable {
        /// Pinned to the leading edge, in order.
        case leading
        /// Sits just before the centered zoom group, in order.
        case beforeZoom
        /// Pinned to the trailing edge, in order.
        case trailing
    }

    let id: Identifier
    let placement: Placement
    /// Fixed width, when the control needs one. `nil` means it sizes itself.
    let width: CGFloat?

    /// Whether this control is shown for a given chrome state — the same rules
    /// `ReaderChromeState` already owns, read here so layout and visibility can
    /// never disagree.
    func isVisible(in state: ReaderChromeState) -> Bool {
        switch id {
        case .cover:
            return state.showsCover
        case .title, .readAloud, .pageLayout, .crop:
            // Title and Read are always present; page layout and crop follow the
            // PDF-only visibility owned by the chrome state.
            return visibilityFromChromeState(state)
        case .relatedFormsToggle:
            return state.showsRelatedFormsToggle
        case .readAloudStop:
            return state.showsReadAloudStopButton
        }
    }

    private func visibilityFromChromeState(_ state: ReaderChromeState) -> Bool {
        switch id {
        case .pageLayout: return state.showsPageLayoutButton
        case .crop: return state.showsCropButton
        default: return true
        }
    }
}

/// The reader toolbar's composition, in one place.
enum ReaderToolbarLayout {
    /// Spacing between controls inside a cluster.
    static let clusterSpacing: CGFloat = 8
    /// Spacing between the cover/title pair, which reads as one unit.
    static let titleClusterSpacing: CGFloat = 10
    /// Gap between the trailing edge of the window and the last control.
    static let trailingInset: CGFloat = 14
    /// Gap between the leading edge of the window and the cover.
    static let leadingInset: CGFloat = 128
    /// Gap between the `beforeZoom` cluster and the zoom group.
    static let beforeZoomGap: CGFloat = 14

    /// Every toolbar control, in visual order within its cluster.
    ///
    /// To move a control, move its entry. To add one, append it here and build
    /// its view in `ReaderWindowController.toolbarView(for:)`.
    static let items: [ReaderToolbarItem] = [
        ReaderToolbarItem(id: .cover, placement: .leading, width: 28),
        ReaderToolbarItem(id: .title, placement: .leading, width: nil),

        ReaderToolbarItem(id: .relatedFormsToggle, placement: .beforeZoom, width: nil),
        ReaderToolbarItem(id: .readAloud, placement: .beforeZoom, width: 82),
        ReaderToolbarItem(id: .readAloudStop, placement: .beforeZoom, width: 82),

        ReaderToolbarItem(id: .pageLayout, placement: .trailing, width: 84),
        ReaderToolbarItem(id: .crop, placement: .trailing, width: 84)
    ]

    static func items(in placement: ReaderToolbarItem.Placement) -> [ReaderToolbarItem] {
        items.filter { $0.placement == placement }
    }

    /// The controls actually shown for a chrome state, in order.
    static func visibleItems(
        in placement: ReaderToolbarItem.Placement,
        state: ReaderChromeState
    ) -> [ReaderToolbarItem.Identifier] {
        items(in: placement).filter { $0.isVisible(in: state) }.map(\.id)
    }
}
