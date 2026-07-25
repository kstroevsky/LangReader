import Observation
import SwiftUI

/// One saved word in the trainer's list.
///
/// Everything here is already display-ready. The AppKit card computed these
/// inline while building views — the status line, the truncated answer, the
/// disclosure title with its form count — so the same string was both derived
/// and rendered in one place and could not be checked independently.
struct VocabularyWordRow: Identifiable {
    /// The canonical key for the word, also what the occurrence expansion is
    /// keyed by.
    let id: String
    let word: String
    let location: String
    let status: String
    let hasPronunciation: Bool
    /// Rendered markdown, capped as the card capped it. Nil when the word has
    /// no answer saved yet.
    let answer: AttributedString?
    let occurrences: [Occurrence]
    let isExpanded: Bool
    /// How many distinct inflected forms were seen, shown before the occurrence
    /// count when there is more than one.
    let formCount: Int
    /// The ids the delete action applies to; a row can group several records.
    let recordIDs: [String]

    struct Occurrence: Identifiable {
        let id: String
        let location: String
        let context: AttributedString
    }

    /// "Forms (3) · Occurrences (12) ▼"
    var disclosureTitle: String {
        let formPrefix = formCount > 1
            ? AppText.localized("词形（\(formCount)） · ", "Forms (\(formCount)) · ")
            : ""
        let arrow = isExpanded ? "▲" : "▼"
        return AppText.localized(
            "\(formPrefix)出现位置（\(occurrences.count)） \(arrow)",
            "\(formPrefix)Occurrences (\(occurrences.count)) \(arrow)"
        )
    }
}

/// What a row's controls do. The controller owns the side effects (clipboard,
/// SRS, navigation); this only names the intent.
enum VocabularyWordListAction: Equatable {
    case speak(word: String)
    case copy(word: String)
    case delete(recordIDs: [String])
    case toggleOccurrences(key: String)
    case openOccurrence(id: String)
    case previousPage
    case nextPage
}

/// State behind the trainer's word list.
@Observable
final class VocabularyWordListModel {
    var rows: [VocabularyWordRow] = []
    /// Shown instead of the rows when the filter matches nothing.
    var emptyMessage: String?

    var pageIndex = 0
    var pageCount = 1
    var totalCount = 0

    var showsPagination: Bool { pageCount > 1 }
    var canGoBack: Bool { pageIndex > 0 }
    var canGoForward: Bool { pageIndex + 1 < pageCount }

    var pageLabel: String {
        AppText.localized(
            "第 \(pageIndex + 1) / \(pageCount) 页 · 共 \(totalCount) 个",
            "Page \(pageIndex + 1) / \(pageCount) · \(totalCount) total"
        )
    }

    @ObservationIgnored var action: ((VocabularyWordListAction) -> Void)?
}
