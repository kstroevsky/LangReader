import Foundation

package struct VocabularyLanguageRecognitionObservation: Sendable {
    package let dominant: VocabularyLanguageCandidate?
    package let candidates: [VocabularyLanguageCandidate]

    package init(
        dominant: VocabularyLanguageCandidate?,
        candidates: [VocabularyLanguageCandidate]
    ) {
        self.dominant = dominant
        self.candidates = candidates
    }
}

package protocol VocabularyLanguageRecognizing: Sendable {
    var descriptor: VocabularyProviderDescriptor { get }
    func recognize(sample: String) throws -> VocabularyLanguageRecognitionObservation
}

/// Samples representative document prose and turns recognizer observations
/// into an explicit language resolution. Product capability policy deliberately
/// lives elsewhere: a recognizer may resolve a language even when preparation
/// is unavailable for it.
package enum VocabularyLanguageDetector {
    package static let maxSampledPages = 16
    package static let maxScoredPagesUsed = 8
    package static let maxSampleCharacters = 8_000
    package static let minimumProseWords = 60
    package static let minimumRecognitionCharacters = 40

    package static func resolution<R: VocabularyLanguageRecognizing>(
        forSample sample: String,
        sampledUnitCount: Int = 1,
        recognizer: R
    ) -> VocabularyLanguageResolution {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumRecognitionCharacters else {
            return .undetermined(.unresolved(
                .insufficientText,
                sampledCharacterCount: trimmed.count,
                sampledUnitCount: sampledUnitCount
            ))
        }

        do {
            let observation = try recognizer.recognize(sample: trimmed)
            let evidence = VocabularyLanguageEvidence(
                provider: recognizer.descriptor,
                candidates: observation.candidates,
                sampledCharacterCount: trimmed.count,
                sampledUnitCount: sampledUnitCount,
                undeterminedReason: observation.dominant == nil ? .inconclusiveRecognition : nil
            )
            guard let dominant = observation.dominant else {
                return .undetermined(evidence)
            }
            return .resolved(VocabularyResolvedLanguage(
                id: dominant.language,
                provenance: .automaticDetection,
                evidence: evidence
            ))
        } catch {
            return .undetermined(VocabularyLanguageEvidence(
                provider: recognizer.descriptor,
                sampledCharacterCount: trimmed.count,
                sampledUnitCount: sampledUnitCount,
                undeterminedReason: .providerFailure
            ))
        }
    }

    package static func resolution<R: VocabularyLanguageRecognizing>(
        pageCount: Int,
        pageText: (Int) -> String?,
        recognizer: R
    ) -> VocabularyLanguageResolution {
        guard pageCount > 0 else {
            return .undetermined(.unresolved(.insufficientText))
        }

        let indices = sampleIndices(pageCount: pageCount)
        let scored = indices.compactMap { index -> (score: Int, text: String)? in
            guard let text = pageText(index), !text.isEmpty else { return nil }
            let score = proseScore(text)
            return score > 0 ? (score, text) : nil
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.text < $1.text
        }

        var sampledUnits = 0
        var sample = ""
        for page in scored.prefix(maxScoredPagesUsed) {
            guard sample.count < maxSampleCharacters else { break }
            sample.append(page.text)
            sample.append("\n")
            sampledUnits += 1
        }
        if sample.isEmpty {
            for index in indices {
                guard sample.count < maxSampleCharacters else { break }
                if let text = pageText(index), !text.isEmpty {
                    sample.append(text)
                    sample.append("\n")
                    sampledUnits += 1
                }
            }
        }
        return resolution(
            forSample: String(sample.prefix(maxSampleCharacters)),
            sampledUnitCount: sampledUnits,
            recognizer: recognizer
        )
    }

    package static func resolution<R: VocabularyLanguageRecognizing>(
        forContexts contexts: [String],
        recognizer: R
    ) -> VocabularyLanguageResolution {
        var sample = ""
        var sampledUnits = 0
        for context in contexts {
            guard sample.count < maxSampleCharacters else { break }
            let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sample.append(trimmed)
            sample.append("\n")
            sampledUnits += 1
        }
        return resolution(
            forSample: String(sample.prefix(maxSampleCharacters)),
            sampledUnitCount: sampledUnits,
            recognizer: recognizer
        )
    }

    package static func sampleIndices(pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        guard pageCount > 4 else { return Array(0..<pageCount) }

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

    package static func proseScore(_ text: String) -> Int {
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

        let letterRatio = (letters * 100) / nonSpace
        guard letterRatio >= 60 else { return 0 }
        return substantialWords * letterRatio
    }
}
