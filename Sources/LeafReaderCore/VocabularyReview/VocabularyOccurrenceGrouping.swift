import Foundation
import LeafReaderCore

/// One inflected spelling of a saved word, and how often it was met.
package struct OccurrenceFormGroup: Equatable {
    package let key: String
    package let surface: String
    package let label: GermanFormLabel?
    package let count: Int
}

/// Groups a word's occurrences by the exact spelling that was highlighted.
///
/// This drives the form filter tabs in the vocabulary library ("All (108) ·
/// kommen (37) · kam (9) …"). It ran inside the library window, so the rules it
/// encodes — which spellings collapse together, what order the tabs appear in,
/// and where the counts come from — could not be checked without opening it.
package enum VocabularyOccurrenceGrouping {
    /// Counts come from the occurrences themselves rather than the record's
    /// form list, so every tab's number matches the rows it actually reveals.
    /// The two can disagree: the form list is built from a dictionary, the
    /// occurrences from what is really in the document.
    package static func formGroups(
        record: VocabularyLibraryRecord,
        occurrences: [VocabularyLibraryOccurrence]
    ) -> [OccurrenceFormGroup] {
        let labelsByKey = labels(for: record)

        // First-encounter order, not alphabetical: the tabs then follow the
        // order the reader met the forms in the document, and a tab does not
        // jump position when a new occurrence is saved.
        var order: [String] = []
        var surfaces: [String: String] = [:]
        var counts: [String: Int] = [:]
        for occurrence in occurrences {
            // An occurrence with no recorded spelling predates surface-form
            // tracking; the saved word is the best available answer.
            let surface = occurrence.surfaceForm ?? record.word
            let key = VocabularyTextPolicy.canonicalVocabularyKey(surface)
            guard !key.isEmpty else { continue }
            if counts[key] == nil {
                order.append(key)
                surfaces[key] = surface
            }
            counts[key, default: 0] += 1
        }

        return order.map { key in
            OccurrenceFormGroup(
                key: key,
                surface: surfaces[key] ?? key,
                label: labelsByKey[key],
                count: counts[key] ?? 0
            )
        }
    }

    /// Labels come from the record's form list, keyed the same way the
    /// occurrences are, so a label written as "Kommen" still finds "kommen".
    /// The first label wins: a key repeated in the form list is a dictionary
    /// ambiguity, and picking later ones would make the tab flip label between
    /// reloads.
    package static func labels(for record: VocabularyLibraryRecord) -> [String: GermanFormLabel] {
        var labelsByKey: [String: GermanFormLabel] = [:]
        for form in record.forms {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(form.surface)
            if let label = form.label, labelsByKey[key] == nil {
                labelsByKey[key] = label
            }
        }
        return labelsByKey
    }
}
