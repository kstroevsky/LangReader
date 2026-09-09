import Foundation
import LeafReaderCore
import NaturalLanguage

private struct Fixture: Decodable {
    let schemaVersion: Int
    let release: String
    let cases: [Case]
}

private struct Case: Decodable {
    let caseID: String
    let sourceID: String
    let sourceSentenceID: String
    let languageCode: String
    let text: String
    let surface: String
    let goldLemma: String
    let goldUPOS: String
    let goldXPOS: String
    let goldFeatures: String
    let occurrenceWeight: Int
}

private struct CaseResult: Codable {
    let caseID: String
    let languageCode: String
    let sourceSentenceID: String
    let surface: String
    let goldLemma: String
    let goldUPOS: String
    let goldFeatures: String
    let expectedPartOfSpeech: String
    let predictedPartOfSpeech: String
    let predictedLemma: String?
    let leadingProbability: Double
    let margin: Double
    let abstained: Bool
    let rawTagCorrect: Bool
    let finalIdentityCorrect: Bool
    let expectedExcluded: Bool
    let predictedExcluded: Bool
    let occurrenceWeight: Int
}

private struct LanguageConsequence: Codable {
    let languageCode: String
    let goldOccurrenceDenominator: Int
    let predictedOccurrenceDenominator: Int
    let denominatorDelta: Int
    let erroneousExcludedMass: Int
    let erroneousIncludedMass: Int
    let goldFirstQuestion: String?
    let predictedFirstQuestion: String?
    let questionIdentityChanged: Bool
    let goldSelectedKeys: [String]
    let predictedSelectedKeys: [String]
    let selectedDeckSymmetricDifferenceCount: Int
}

private struct Report: Codable {
    let schemaVersion: Int
    let fixtureRelease: String
    let environment: [String: String]
    let policy: [String: Double]
    let caseResults: [CaseResult]
    let rawTagAccuracy: Double
    let abstentionRate: Double
    let finalIdentityAccuracy: Double
    let occurrenceWeightedFinalIdentityAccuracy: Double
    let confusion: [String: Int]
    let consequences: [LanguageConsequence]
    let limitations: [String]
}

private func expectedPOS(_ upos: String) -> VocabularyPartOfSpeech {
    switch upos {
    case "NOUN", "PROPN": .noun
    case "VERB", "AUX": .verb
    case "ADJ": .adjective
    case "ADV": .adverb
    case "PRON": .pronoun
    case "DET": .determiner
    case "ADP": .preposition
    case "CCONJ", "SCONJ": .conjunction
    case "INTJ": .interjection
    case "PART": .particle
    default: .other
    }
}

private func language(_ code: String) -> NLLanguage {
    code == "de" ? .german : .english
}

private func candidate(key: String, lemma: String, pos: VocabularyPartOfSpeech, weight: Int) -> DocumentVocabularyCandidate {
    DocumentVocabularyCandidate(
        canonicalKey: key,
        displayLemma: lemma,
        lexicalItemID: VocabularyLexicalItemID(language: key.hasPrefix("de|") ? "de" : "en", lemma: lemma, partOfSpeech: pos),
        partOfSpeech: pos,
        observedForms: [VocabularyDocumentObservedForm(surface: lemma, occurrenceCount: weight)],
        occurrenceCount: weight,
        representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: lemma.utf16.count),
        generalFrequencyRank: nil,
        difficulty: 0
    )
}

private func consequence(languageCode: String, cases: [Case], results: [CaseResult]) -> LanguageConsequence {
    let paired = zip(cases, results).filter { $0.0.languageCode == languageCode }
    let gold = paired.compactMap { item -> DocumentVocabularyCandidate? in
        guard !item.1.expectedExcluded else { return nil }
        let pos = expectedPOS(item.0.goldUPOS)
        let id = VocabularyLexicalItemID(language: languageCode, lemma: item.0.goldLemma, partOfSpeech: pos)
        return candidate(key: id.canonicalKey, lemma: item.0.goldLemma, pos: pos, weight: item.0.occurrenceWeight)
    }
    let predicted = paired.compactMap { item -> DocumentVocabularyCandidate? in
        guard !item.1.predictedExcluded, let lemma = item.1.predictedLemma,
              let pos = VocabularyPartOfSpeech(rawValue: item.1.predictedPartOfSpeech) else { return nil }
        let id = VocabularyLexicalItemID(language: languageCode, lemma: lemma, partOfSpeech: pos)
        return candidate(key: id.canonicalKey, lemma: lemma, pos: pos, weight: item.0.occurrenceWeight)
    }
    func assessment(_ values: [DocumentVocabularyCandidate]) -> (String?, [String]) {
        var assessment = AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: languageCode, candidates: values),
            mode: .targetCoverage(0.98)
        )
        let first = assessment.nextQuestion()?.canonicalKey
        let deck = assessment.result().items.filter(\.isSelected).map(\.id).sorted()
        return (first, deck)
    }
    let goldAssessment = assessment(gold)
    let predictedAssessment = assessment(predicted)
    let goldMass = gold.reduce(0) { $0 + $1.occurrenceCount }
    let predictedMass = predicted.reduce(0) { $0 + $1.occurrenceCount }
    let erroneousExcluded = paired.filter { !$0.1.expectedExcluded && $0.1.predictedExcluded }
        .reduce(0) { $0 + $1.0.occurrenceWeight }
    let erroneousIncluded = paired.filter { $0.1.expectedExcluded && !$0.1.predictedExcluded }
        .reduce(0) { $0 + $1.0.occurrenceWeight }
    return LanguageConsequence(
        languageCode: languageCode,
        goldOccurrenceDenominator: goldMass,
        predictedOccurrenceDenominator: predictedMass,
        denominatorDelta: predictedMass - goldMass,
        erroneousExcludedMass: erroneousExcluded,
        erroneousIncludedMass: erroneousIncluded,
        goldFirstQuestion: goldAssessment.0,
        predictedFirstQuestion: predictedAssessment.0,
        questionIdentityChanged: goldAssessment.0 != predictedAssessment.0,
        goldSelectedKeys: goldAssessment.1,
        predictedSelectedKeys: predictedAssessment.1,
        selectedDeckSymmetricDifferenceCount: Set(goldAssessment.1).symmetricDifference(Set(predictedAssessment.1)).count
    )
}

@main
private enum VocabularyPOSEvaluator {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: evaluate-vocabulary-pos-fixtures <fixture.json> <report.json>\n", stderr)
            exit(2)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard fixture.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        var results: [CaseResult] = []
        for item in fixture.cases {
            let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
            tagger.string = item.text
            guard let range = item.text.range(of: item.surface) else { throw CocoaError(.coderReadCorrupt) }
            let hypotheses = tagger.tagHypotheses(at: range.lowerBound, unit: .word, scheme: .lexicalClass, maximumCount: 2).0
            let ordered = hypotheses.sorted { $0.value > $1.value }
            let predictedPOS = VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: hypotheses)
            let index = VocabularyDocumentLemmaIndex(texts: [item.text], language: language(item.languageCode), maximumWorkerCount: 1)
            let summary = index?.lemmaSummaries().first { summary in
                summary.observedForms.contains { $0.surface.caseInsensitiveCompare(item.surface) == .orderedSame }
            }
            let expected = expectedPOS(item.goldUPOS)
            let expectedExcluded = item.goldUPOS == "PROPN"
            let predictedExcluded = summary == nil || summary?.isConfidentName == true
            let predictedLemma = summary?.lemmaKey
            results.append(CaseResult(
                caseID: item.caseID,
                languageCode: item.languageCode,
                sourceSentenceID: item.sourceSentenceID,
                surface: item.surface,
                goldLemma: item.goldLemma.lowercased(),
                goldUPOS: item.goldUPOS,
                goldFeatures: item.goldFeatures,
                expectedPartOfSpeech: expected.rawValue,
                predictedPartOfSpeech: predictedPOS.rawValue,
                predictedLemma: predictedLemma,
                leadingProbability: ordered.first?.value ?? 0,
                margin: (ordered.first?.value ?? 0) - (ordered.dropFirst().first?.value ?? 0),
                abstained: predictedPOS == .unknown,
                rawTagCorrect: predictedPOS == expected,
                finalIdentityCorrect: expectedExcluded
                    ? predictedExcluded
                    : !predictedExcluded && predictedLemma == item.goldLemma.lowercased() && summary?.partOfSpeech == expected,
                expectedExcluded: expectedExcluded,
                predictedExcluded: predictedExcluded,
                occurrenceWeight: item.occurrenceWeight
            ))
        }
        let totalWeight = results.reduce(0) { $0 + $1.occurrenceWeight }
        let report = Report(
            schemaVersion: 1,
            fixtureRelease: fixture.release,
            environment: ["os": ProcessInfo.processInfo.operatingSystemVersionString],
            policy: ["minimumLeadingProbability": VocabularyPartOfSpeechConfidencePolicy.minimumLeadingProbability, "minimumMargin": VocabularyPartOfSpeechConfidencePolicy.minimumMargin],
            caseResults: results,
            rawTagAccuracy: Double(results.filter(\.rawTagCorrect).count) / Double(results.count),
            abstentionRate: Double(results.filter(\.abstained).count) / Double(results.count),
            finalIdentityAccuracy: Double(results.filter(\.finalIdentityCorrect).count) / Double(results.count),
            occurrenceWeightedFinalIdentityAccuracy: Double(results.filter(\.finalIdentityCorrect).reduce(0) { $0 + $1.occurrenceWeight }) / Double(totalWeight),
            confusion: Dictionary(grouping: results, by: { "\($0.expectedPartOfSpeech)->\($0.predictedPartOfSpeech)" }).mapValues(\.count),
            consequences: ["en", "de"].map { consequence(languageCode: $0, cases: fixture.cases, results: results) },
            limitations: ["Eight selected UD tokens are adversarial engineering fixtures, not a representative POS accuracy estimate.", "German GSD lemmas are upstream annotations with known provenance limits; final identity results do not establish sense correctness.", "NaturalLanguage behavior is OS-dependent and must be rerun after relevant macOS changes."]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }
}
