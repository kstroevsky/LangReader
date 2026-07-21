import Foundation

enum VocabularyTextPolicy {
    private static let wordTokenPattern = #"\p{L}[\p{L}\p{M}]*(?:['’–—-](?=\p{L})\p{L}[\p{L}\p{M}]*)*"#
    private static let singleWordPattern = #"^"# + wordTokenPattern + #"$"#
    private static let vocabularySelectionPattern = #"^"# + wordTokenPattern + #"(\s+"# + wordTokenPattern + #"){0,4}$"#
    private static let wordBoundaryBefore = #"(?<![\p{L}\p{M}'’–—-])"#
    private static let wordBoundaryAfter = #"(?![\p{L}\p{M}'’–—-])"#
    private static let comparisonLocale = Locale(identifier: "de_DE")

    static let maxSingleWordLength = 40
    static let maxVocabularySelectionLength = 80

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedVocabularyText(_ text: String) -> String {
        // Fast path for single tokens, which is what the occurrence scanner
        // feeds this millions of times over a document. Both passes below key
        // off whitespace — `joinLineBrokenHyphens` needs `\s+` after a hyphen,
        // `collapsedWhitespace` collapses runs of it, and both then trim — so
        // with no whitespace present the result is the input unchanged.
        if !text.contains(where: \.isWhitespace) { return text }
        return collapsedWhitespace(joinLineBrokenHyphens(text))
    }

    static func canonicalVocabularyKey(_ text: String) -> String {
        normalizedVocabularyText(text)
            .precomposedStringWithCanonicalMapping
            .lowercased(with: comparisonLocale)
    }

    /// Whether `surface` is the group's base form spelled identically, case and
    /// diacritics included. Used to gate the "surface equals lemma" occurrence
    /// shortcut: unlike `canonicalVocabularyKey`, it does NOT fold case, so the
    /// German noun "Folgen" (lemma "Folge") is not mistaken for the verb lemma
    /// "folgen". Capitalization is the noun/verb signal and must be preserved.
    static func surfaceMatchesLemmaExactly(_ surface: String, _ lemma: String) -> Bool {
        normalizedVocabularyText(surface).precomposedStringWithCanonicalMapping
            == normalizedVocabularyText(lemma).precomposedStringWithCanonicalMapping
    }

    static func normalizedOccurrenceText(_ text: String, matching query: String) -> String {
        let normalizedQuery = normalizedVocabularyText(query)
        let hasGenuineHyphen = normalizedQuery.range(of: #"[‐‑‒–—-]"#, options: .regularExpression) != nil
        let value = hasGenuineHyphen
            ? joinLineBrokenHyphens(text)
            : removeLineBrokenHyphens(text)
        return collapsedWhitespace(value)
    }

    static func normalizedPDFVocabularyText(
        _ text: String,
        lineBrokenHyphenRange: NSRange? = nil,
        isKnownHyphenatedWord: (String) -> Bool = { _ in false },
        isKnownWord: (String) -> Bool = { _ in false }
    ) -> String {
        let lineBrokenText = textByMarkingLineBrokenHyphen(text, range: lineBrokenHyphenRange)
        guard containsLineBrokenHyphen(lineBrokenText) else {
            return normalizedVocabularyText(text)
        }
        let candidates = lineBrokenHyphenNormalizationCandidates(for: lineBrokenText)
        let dehyphenated = candidates.dehyphenated
        let hyphenated = candidates.hyphenated
        if isSingleEnglishWord(dehyphenated) {
            if isKnownWord(dehyphenated) {
                return dehyphenated
            }
            if isKnownHyphenatedWord(hyphenated) {
                return hyphenated
            }
            if shouldPreferDehyphenatedLineBreak(original: lineBrokenText, dehyphenated: dehyphenated) {
                return dehyphenated
            }
        }
        return hyphenated
    }

    static func normalizedPDFContextText(
        _ text: String,
        isKnownHyphenatedWord: (String) -> Bool = { _ in false },
        isKnownWord: (String) -> Bool = { _ in false }
    ) -> String {
        let value = normalized(text)
        guard !value.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: #"\p{L}[\p{L}\p{M}]*[‐‑-]\s+\p{L}[\p{L}\p{M}]*"#
              ) else {
            return value
        }

        let result = NSMutableString(string: value)
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            let rawWord = result.substring(with: match.range)
            let replacement = normalizedPDFVocabularyText(
                rawWord,
                isKnownHyphenatedWord: isKnownHyphenatedWord,
                isKnownWord: isKnownWord
            )
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return collapsedWhitespace(result as String)
    }

    static func isSingleEnglishWord(_ text: String) -> Bool {
        let value = normalizedVocabularyText(text)
        guard value.count <= maxSingleWordLength else { return false }
        return value.range(of: singleWordPattern, options: .regularExpression) != nil
    }

    static func speakableWord(_ text: String) -> String? {
        let value = normalizedVocabularyText(text)
        return isSingleEnglishWord(value) ? value : nil
    }

    static func isVocabularySelection(_ text: String) -> Bool {
        let value = normalizedVocabularyText(text)
        guard value.count <= maxVocabularySelectionLength else { return false }
        let words = value.split { $0.isWhitespace || $0.isNewline }
        guard (1...5).contains(words.count) else { return false }
        return value.range(of: vocabularySelectionPattern, options: .regularExpression) != nil
    }

    /// Whether `surfaceForm` appears in `context` but *only ever inside a larger
    /// word*, never as a whole word (e.g. "folg" within "Erfolg", or "Abteilung"
    /// within "IT-Abteilung"). This is the cheap first gate for the load-time
    /// prune of pre-fix recognizer artifacts: a surface that stands as a whole
    /// word is unconditionally a real occurrence and needs no further checking.
    ///
    /// Deliberately conservative — it returns `false` (not a candidate) whenever
    /// it cannot be certain: an empty surface or context, or a surface the
    /// context does not contain at all. A `true` result only marks the record as
    /// a *candidate*; whether it is genuinely stale is decided by re-running the
    /// matcher against the context (a same-line compound like "IT-Abteilung"
    /// still reproduces "Abteilung" and must be kept).
    static func surfaceOccursOnlyWithinLargerWord(surface surfaceForm: String, context: String) -> Bool {
        let surface = normalizedVocabularyText(surfaceForm)
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !surface.isEmpty, !trimmedContext.isEmpty, isSingleEnglishWord(surface) else {
            return false
        }
        // The surface must occur in the context at all; if it does not, the
        // stored context does not describe this surface and we leave it alone.
        guard trimmedContext.range(of: surface, options: [.caseInsensitive]) != nil else {
            return false
        }
        guard let pattern = boundedSearchPattern(for: surface),
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(trimmedContext.startIndex..<trimmedContext.endIndex, in: trimmedContext)
        // A whole-word occurrence anywhere ⇒ it is a real word ⇒ not a candidate.
        return regex.firstMatch(in: trimmedContext, range: range) == nil
    }

    static func shouldUseSystemTTSForShortSelection(_ text: String) -> Bool {
        let words = text
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
        guard (1...4).contains(words.count) else { return false }
        return text.range(of: #"[.!?]"#, options: .regularExpression) == nil
    }

    static func boundedSearchPattern(for query: String) -> String? {
        let value = normalized(query)
        guard !value.isEmpty else { return nil }
        let words = value.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard !words.isEmpty else { return nil }
        let escaped = words
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        return #"(?i)"# + wordBoundaryBefore + escaped + wordBoundaryAfter
    }

    static func boundedPrefixPattern(for prefix: String) -> String {
        wordBoundaryBefore + NSRegularExpression.escapedPattern(for: normalized(prefix))
    }

    static func lineBrokenHyphenWordPattern(prefix: String) -> String {
        boundedPrefixPattern(for: prefix) + #"(?<layoutHyphen>[‐‑‒–—-])\s*"# + wordTokenPattern
    }

    static func lineBrokenHyphenWordPattern(suffix: String) -> String {
        wordBoundaryBefore
            + wordTokenPattern
            + #"(?<layoutHyphen>[‐‑‒–—-])\s*"#
            + NSRegularExpression.escapedPattern(for: normalized(suffix))
            + wordBoundaryAfter
    }

    static func pdfSearchQueries(for query: String) -> [String] {
        let value = normalized(query)
        guard !value.isEmpty else { return [] }

        let joined = collapsedWhitespace(joinLineBrokenHyphens(value))
        var results: [String] = []
        appendUnique(value, to: &results)
        appendUnique(collapsedWhitespace(value), to: &results)
        appendUnique(joined, to: &results)
        for lineBreakVariant in lineBreakHyphenVariants(for: joined) {
            appendUnique(lineBreakVariant, to: &results)
        }
        return results
    }

    static func lineBrokenDehyphenatedSearchPattern(for query: String) -> String? {
        let value = normalized(query)
        guard isSingleEnglishWord(value), !value.contains("-"), value.count >= 4 else {
            return nil
        }
        let characters = Array(value)
        let variants = (1..<characters.count).map { index in
            NSRegularExpression.escapedPattern(for: String(characters[..<index]))
                + #"[‐‑‒–—-]\s*"#
                + NSRegularExpression.escapedPattern(for: String(characters[index...]))
        }
        guard !variants.isEmpty else { return nil }
        return #"(?i)"# + wordBoundaryBefore + "(?:" + variants.joined(separator: "|") + ")" + wordBoundaryAfter
    }

    static func emphasisPattern(for word: String) -> String {
        let value = normalized(word)
        let escaped = NSRegularExpression.escapedPattern(for: value)
        guard isSingleEnglishWord(value) else { return escaped }
        return wordBoundaryBefore + escaped + wordBoundaryAfter
    }

    static func dehyphenatedPDFLayoutCandidate(word rawWord: String, context: String?) -> String? {
        let word = normalizedVocabularyText(rawWord)
        guard let context, !word.isEmpty, !context.isEmpty else { return nil }

        let nsWord = word as NSString
        guard let regex = try? NSRegularExpression(pattern: #"[‐‑‒–—-]"#) else { return nil }

        for match in regex.matches(in: word, range: NSRange(location: 0, length: nsWord.length)).reversed() {
            let spacedWord = nsWord.replacingCharacters(in: NSRange(location: NSMaxRange(match.range), length: 0), with: " ")
            guard context.range(of: spacedWord, options: [.caseInsensitive]) != nil else { continue }

            let candidate = nsWord.replacingCharacters(in: match.range, with: "")
            guard isSingleEnglishWord(candidate) else { continue }
            return candidate
        }
        return nil
    }

    private static func collapsedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func textByMarkingLineBrokenHyphen(_ text: String, range: NSRange?) -> String {
        guard let range,
              range.location >= 0,
              NSMaxRange(range) <= (text as NSString).length,
              let swiftRange = Range(range, in: text),
              String(text[swiftRange]).range(of: #"[‐‑‒–—-]"#, options: .regularExpression) != nil else {
            return text
        }
        let nsText = text as NSString
        return nsText.replacingCharacters(
            in: NSRange(location: NSMaxRange(range), length: 0),
            with: "\n"
        )
    }

    private static func containsLineBrokenHyphen(_ value: String) -> Bool {
        value.range(of: #"[‐‑‒–—-]\s+"#, options: .regularExpression) != nil
    }

    private static func lineBrokenHyphenNormalizationCandidates(for value: String) -> (hyphenated: String, dehyphenated: String) {
        (
            hyphenated: collapsedWhitespace(joinLineBrokenHyphens(value)),
            dehyphenated: collapsedWhitespace(removeLineBrokenHyphens(value))
        )
    }

    private static func joinLineBrokenHyphens(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[‐‑‒–—-]\s+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeLineBrokenHyphens(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[‐‑‒–—-]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldPreferDehyphenatedLineBreak(original: String, dehyphenated: String) -> Bool {
        guard isSingleEnglishWord(dehyphenated),
              let match = original.range(
                of: #"(?i)\p{L}[\p{L}\p{M}]*[‐‑‒–—-]\s+\p{L}[\p{L}\p{M}]*"#,
                options: .regularExpression
              ) else {
            return false
        }
        let prefix = String(original[match])
            .replacingOccurrences(of: #"[‐‑‒–—-]\s+.*$"#, with: "", options: .regularExpression)
        return prefix.count <= 3
    }

    private static func lineBreakHyphenVariants(for value: String) -> [String] {
        let normalizedValue = collapsedWhitespace(value)
        guard normalizedValue.contains("-") else { return [] }
        return [
            normalizedValue.replacingOccurrences(of: "-", with: "-\n"),
            normalizedValue.replacingOccurrences(of: "-", with: "- ")
        ]
    }

    private static func appendUnique(_ value: String, to results: inout [String]) {
        guard !value.isEmpty else { return }
        if !results.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            results.append(value)
        }
    }
}
