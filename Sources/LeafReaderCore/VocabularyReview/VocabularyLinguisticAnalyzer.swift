import Foundation

/// Provider-neutral linguistic evidence for one token in a document text unit.
/// Ranges are UTF-16 offsets into the analyzed string so renderers and native
/// language providers can exchange evidence without sharing native objects.
package struct VocabularyLinguisticTokenEvidence: Sendable, Equatable {
    package let range: NSRange
    package let taggedLemma: String?
    package let lexicalClassHypotheses: [String: Double]
    package let isConfidentName: Bool

    package init(
        range: NSRange,
        taggedLemma: String?,
        lexicalClassHypotheses: [String: Double] = [:],
        isConfidentName: Bool = false
    ) {
        self.range = range
        self.taggedLemma = taggedLemma
        self.lexicalClassHypotheses = lexicalClassHypotheses
        self.isConfidentName = isConfidentName
    }
}

/// A worker-local linguistic analyzer. Implementations may own mutable native
/// analyzers, but one instance is never shared between document-index workers.
package protocol VocabularyLinguisticAnalyzing: Sendable {
    func tokenEvidence(
        in text: String,
        language: VocabularyLanguageID
    ) -> [VocabularyLinguisticTokenEvidence]

    func isolatedLemma(
        for surfaceForm: String,
        language: VocabularyLanguageID
    ) -> String?
}

/// Creates one analyzer per worker. Provider selection happens before a build;
/// the hot token loop only uses the concrete analyzer returned here.
package struct VocabularyLinguisticAnalyzerFactory: Sendable {
    private let builder: @Sendable () -> any VocabularyLinguisticAnalyzing

    package init(_ builder: @escaping @Sendable () -> any VocabularyLinguisticAnalyzing) {
        self.builder = builder
    }

    package func makeAnalyzer() -> any VocabularyLinguisticAnalyzing {
        builder()
    }

    /// Safe degradation when no linguistic provider is available. It preserves
    /// exact Unicode token surfaces while supplying no lemma, POS, or name
    /// evidence, so downstream policy can abstain instead of guessing.
    package static let exactForm = VocabularyLinguisticAnalyzerFactory {
        VocabularyExactFormLinguisticAnalyzer()
    }
}

private struct VocabularyExactFormLinguisticAnalyzer: VocabularyLinguisticAnalyzing {
    private static let tokenPattern = #"\p{L}[\p{L}\p{M}]*(?:['’–—-](?=\p{L})\p{L}[\p{L}\p{M}]*)*"#

    func tokenEvidence(
        in text: String,
        language: VocabularyLanguageID
    ) -> [VocabularyLinguisticTokenEvidence] {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: Self.tokenPattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ).map {
            VocabularyLinguisticTokenEvidence(range: $0.range, taggedLemma: nil)
        }
    }

    func isolatedLemma(
        for surfaceForm: String,
        language: VocabularyLanguageID
    ) -> String? {
        nil
    }
}
