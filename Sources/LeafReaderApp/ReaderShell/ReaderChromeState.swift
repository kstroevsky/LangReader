import Foundation

/// What the reader's chrome should show, derived from reader state.
///
/// Visibility rules used to be imperative mutations scattered across the load
/// paths — the same three `isHidden` assignments repeated in the PDF branch, the
/// web branch, and the empty-document reset. Adding one control meant finding
/// and mirroring every site, and missing one failed silently: the control simply
/// lingered on a document it did not belong to.
///
/// Concentrating the rules in one value type makes them reviewable in a single
/// place and testable without AppKit, in the same spirit as
/// `SelectionToolbarConfiguration`. Rendering stays in the controller: this type
/// decides *what* is shown, never *how*.
struct ReaderChromeState: Equatable {
    /// What kind of document the reader is presenting, if any.
    enum Presentation: Equatable {
        case empty
        case pdf
        case web
    }

    let presentation: Presentation
    let showsCover: Bool
    let showsPageLayoutButton: Bool
    let showsCropButton: Bool
    let showsRelatedFormsToggle: Bool
    let showsReadAloudStopButton: Bool
    /// Reflects the persisted preference onto the toggle when it is shown.
    let relatedFormsToggleIsOn: Bool

    /// The empty state the reader shows with no document open.
    static let empty = ReaderChromeState.make(presentation: .empty)

    static func make(
        presentation: Presentation,
        isReadAloudActive: Bool = false,
        showsRelatedWordForms: Bool = true,
        hasCoverImage: Bool = true
    ) -> ReaderChromeState {
        // Page layout, margin crop and the related-forms toggle are all PDF-only:
        // the first two act on PDFKit, and inflected-form markings are only
        // produced for PDF vocabulary.
        let isPDF = presentation == .pdf
        return ReaderChromeState(
            presentation: presentation,
            showsCover: presentation != .empty && hasCoverImage,
            showsPageLayoutButton: isPDF,
            showsCropButton: isPDF,
            showsRelatedFormsToggle: isPDF,
            showsReadAloudStopButton: presentation != .empty && isReadAloudActive,
            relatedFormsToggleIsOn: showsRelatedWordForms
        )
    }

    /// The presentation a document kind maps to.
    static func presentation(for kind: ReaderDocumentKind) -> Presentation {
        kind == .pdf ? .pdf : .web
    }
}
