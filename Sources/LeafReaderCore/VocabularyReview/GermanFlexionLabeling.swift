import Foundation
import LeafReaderCore

// Bridges parsed Wiktionary flexion tables to form labels.
//
// This lives apart from GermanFormLabeler so the offline labeler stays free of
// any dependency on the dictionary tier: callers that only need offline
// labeling — and the test binaries that build them — compile without the
// Wiktionary parser at all.
extension GermanFormLabeler {

    /// Resolves a label from a Wiktionary flexion table, which is authoritative
    /// where the offline rules can only guess: it separates Präsens from
    /// Präteritum, and it names the plurals the morphological rule declines to
    /// claim, such as `Häuser`, `Probleme` and `Autos`.
    ///
    /// A surface form often matches several parameters — `gehe` is both
    /// `Präsens_ich` and `Imperativ Singular*` — so matches resolve in a fixed
    /// priority order rather than by whichever happens to appear first.
    static func label(
        surfaceForm: String,
        using table: GermanWiktionaryParser.FlexionTable
    ) -> GermanFormLabel? {
        let target = VocabularyTextPolicy.canonicalVocabularyKey(surfaceForm)
        guard !target.isEmpty else { return nil }
        return resolve(
            parameters: table.forms
                .filter { VocabularyTextPolicy.canonicalVocabularyKey($0.surface) == target }
                .map(\.label)
        )
    }

    /// Labels a surface form using the cached flexion tables, falling back to
    /// the offline rules.
    ///
    /// The cache wins when it has an answer because it resolves what the
    /// offline rules provably cannot: Präsens versus Präteritum, and the
    /// plurals that are spelled identically to a genitive or dative singular.
    /// When the cache is empty — the common case until a word has been looked
    /// up — behavior is exactly the offline path.
    /// Picks the best label among the parameters naming one surface form.
    ///
    /// Internal rather than private so the store-backed resolver, which lives
    /// alongside the SQLite cache, shares exactly this priority order.
    static func resolve(parameters: [String]) -> GermanFormLabel? {
        let matched = parameters.compactMap { formLabel(forParameter: $0) }
        guard !matched.isEmpty else { return nil }
        let priority: [GermanFormLabel] = [
            .partizipII, .praeteritum, .praesens, .plural, .infinitiv, .grundform
        ]
        return priority.first { matched.contains($0) } ?? matched.first
    }

    static func formLabel(forParameter parameter: String) -> GermanFormLabel? {
        if parameter == "Partizip II" { return .partizipII }
        if parameter.hasPrefix("Präteritum_") { return .praeteritum }
        if parameter.hasPrefix("Präsens_") { return .praesens }
        if parameter.hasSuffix(" Plural") { return .plural }
        if parameter == "Nominativ Singular" { return .grundform }
        // Genitive, dative and accusative singulars are real forms, but there is
        // no case-level label to report them under, so they stay unlabeled
        // rather than being flattened into a misleading one.
        return nil
    }
}
