import NaturalLanguage

/// Picks the language used to lemmatize and group a document's vocabulary.
///
/// The occurrence engine is language-neutral; only the tagger's language
/// differs. We detect the document's dominant language and use it when it is
/// one Apple's tagger lemmatizes well. Anything else falls back to English,
/// the default language, which for non-matching text simply degrades to
/// exact-form matching rather than producing wrong groupings.
enum VocabularyLanguageDetector {
    static let fallback: NLLanguage = .english

    /// Languages allowed for lemma-based inflected-form grouping. Restricting to
    /// a vetted set keeps a mis-detected or poorly-supported language from
    /// scattering a word's forms across bogus lemmas. Italian is deliberately
    /// absent: its lemmas come back inconsistent ("parlo" → "parlarsi" but
    /// "parlato" → "parlare"), which would split one word across two groups.
    static let supported: Set<NLLanguage> = [
        .german, .english, .french, .spanish, .portuguese, .dutch, .russian
    ]

    /// Pages to sample and score. Bounded so detection stays cheap on the
    /// document-load path even for a 250-page book.
    static let maxSampledPages = 16
    /// Best-scoring pages actually fed to the recognizer.
    static let maxScoredPagesUsed = 8
    static let maxSampleCharacters = 8000
    /// Minimum words before a page counts as prose at all.
    static let minimumProseWords = 60

    /// The language to group by, from a representative sample of document text.
    /// Short or empty samples are inconclusive, so they take the fallback.
    static func language(forSample sample: String) -> NLLanguage {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return fallback }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage, supported.contains(dominant) else {
            return fallback
        }
        return dominant
    }

    /// The language for a document, given a way to read page text.
    ///
    /// Sampling the *first* pages is unreliable: front matter is titles, author
    /// lists and copyright boilerplate, and in scanned books it is OCR noise —
    /// a real English art book was detected as Turkish that way. Instead this
    /// spreads its samples across the whole document and keeps the pages that
    /// look most like running prose, which is what the recognizer needs.
    static func language(pageCount: Int, pageText: (Int) -> String?) -> NLLanguage {
        guard pageCount > 0 else { return fallback }

        let indices = sampleIndices(pageCount: pageCount)
        let scored = indices.compactMap { index -> (score: Int, text: String)? in
            guard let text = pageText(index), !text.isEmpty else { return nil }
            let score = proseScore(text)
            return score > 0 ? (score, text) : nil
        }.sorted { $0.score > $1.score }

        var sample = ""
        for page in scored.prefix(maxScoredPagesUsed) {
            guard sample.count < maxSampleCharacters else { break }
            sample.append(page.text)
            sample.append("\n")
        }
        // Nothing looked like prose (an image-only or table-only document):
        // fall back to whatever text there was rather than giving up outright.
        if sample.isEmpty {
            for index in indices {
                guard sample.count < maxSampleCharacters else { break }
                if let text = pageText(index), !text.isEmpty {
                    sample.append(text)
                    sample.append("\n")
                }
            }
        }
        return language(forSample: String(sample.prefix(maxSampleCharacters)))
    }

    /// The language of a document we cannot re-read, inferred from the context
    /// sentences stored with its saved words.
    ///
    /// The Words window lists every document, but only the open one is loaded in
    /// PDFKit. Those saved contexts are real sentences from the document, so
    /// they identify its language well enough to label its forms — and using
    /// them beats labeling another document's words with the open document's
    /// grammar.
    static func language(forContexts contexts: [String]) -> NLLanguage {
        var sample = ""
        for context in contexts {
            guard sample.count < maxSampleCharacters else { break }
            let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sample.append(trimmed)
            sample.append("\n")
        }
        return language(forSample: sample)
    }

    /// Page indices spread across the document, skipping the front matter that
    /// rarely contains running prose.
    static func sampleIndices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        guard pageCount > 4 else { return Array(0..<pageCount) }

        // Skip roughly the first 8% (title/copyright/contents), but never so
        // much that a short document has nothing left.
        let start = min(pageCount / 12, max(0, pageCount - 1))
        let span = pageCount - start
        let count = min(maxSampledPages, span)
        guard count > 0 else { return [] }
        let stride = max(1, span / count)
        var indices: [Int] = []
        var index = start
        while index < pageCount, indices.count < count {
            indices.append(index)
            index += stride
        }
        return indices
    }

    /// How much a page reads like running prose, without assuming any language.
    ///
    /// Counts word-like tokens of three or more letters and scales by how much
    /// of the page is letters rather than digits, punctuation and layout noise.
    /// This keeps tables, figure captions and OCR garbage from outscoring the
    /// body text the recognizer actually needs.
    static func proseScore(_ text: String) -> Int {
        var letters = 0
        var nonSpace = 0
        for character in text where !character.isWhitespace {
            nonSpace += 1
            if character.isLetter { letters += 1 }
        }
        guard nonSpace > 0 else { return 0 }

        let words = text.split { !$0.isLetter && $0 != "'" && $0 != "’" && $0 != "-" }
        let substantialWords = words.filter { $0.count >= 3 }.count
        guard substantialWords >= minimumProseWords else { return 0 }

        // Letter ratio in percent, so the score stays integral.
        let letterRatio = (letters * 100) / nonSpace
        guard letterRatio >= 60 else { return 0 }
        return substantialWords * letterRatio
    }
}
