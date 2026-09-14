import CryptoKit
import Foundation
import LeafReaderCore
import NaturalLanguage

private struct Fixture: Decodable {
    let schemaVersion: Int
    let fixtureID: String?
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
    let evaluationSplit: String?
    let genre: String?
    let isParticiple: Bool?
}

private struct CaseResult: Codable {
    let caseID: String
    let sourceID: String
    let languageCode: String
    let evaluationSplit: String
    let genre: String
    let isParticiple: Bool
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

private struct GroupMetric: Codable {
    let dimension: String
    let value: String
    let caseCount: Int
    let occurrenceWeight: Int
    let rawTagAccuracy: Double
    let abstentionRate: Double
    let finalIdentityAccuracy: Double
    let occurrenceWeightedFinalIdentityAccuracy: Double
}

private struct SplitMergeSummary: Codable {
    let evaluationSplit: String
    let languageCode: String
    let goldIdentityCount: Int
    let predictedIdentityCount: Int
    let missingGoldIdentityCount: Int
    let extraPredictedIdentityCount: Int
    let lemmaPOSSetMismatchCount: Int
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

private struct SplitConsequence: Codable {
    let evaluationSplit: String
    let consequence: LanguageConsequence
}

private struct Report: Codable {
    let schemaVersion: Int
    let fixtureID: String?
    let fixtureSHA256: String
    let fixtureRelease: String
    let environment: [String: String]
    let policy: [String: Double]
    let caseResults: [CaseResult]
    let rawTagAccuracy: Double
    let abstentionRate: Double
    let finalIdentityAccuracy: Double
    let occurrenceWeightedFinalIdentityAccuracy: Double
    let confusion: [String: Int]
    let groupMetrics: [GroupMetric]
    let splitMergeSummaries: [SplitMergeSummary]
    let consequences: [LanguageConsequence]
    let splitConsequences: [SplitConsequence]
    let limitations: [String]
}

private func assessable(
    lemma: String,
    partOfSpeech: VocabularyPartOfSpeech,
    languageCode: String,
    isConfidentName: Bool
) -> Bool {
    let lexical = VocabularyLexicalItemID(
        language: languageCode,
        lemma: lemma,
        partOfSpeech: partOfSpeech
    )
    let summary = VocabularyDocumentLemmaSummary(
        canonicalKey: lexical.canonicalKey,
        lemmaKey: lexical.lemma,
        displayLemma: lemma,
        lexicalItemID: lexical,
        partOfSpeech: partOfSpeech,
        observedForms: [VocabularyDocumentObservedForm(surface: lemma, occurrenceCount: 1)],
        occurrenceCount: 1,
        representativeRange: VocabularyDocumentSourceRange(
            unitIndex: 0,
            utf16Location: 0,
            utf16Length: lemma.utf16.count
        ),
        isConfidentName: isConfidentName
    )
    return !DocumentVocabularyInventory(
        summaries: [summary],
        languageCode: languageCode,
        maximumFrequencyRank: 1,
        rank: { _ in nil }
    ).candidates.isEmpty
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

private func aggregateCandidates(_ values: [DocumentVocabularyCandidate]) -> [DocumentVocabularyCandidate] {
    struct Aggregate {
        let lemma: String
        let partOfSpeech: VocabularyPartOfSpeech
        var weight: Int
    }
    var byKey: [String: Aggregate] = [:]
    for value in values {
        guard let lexicalItemID = value.lexicalItemID else { continue }
        var aggregate = byKey[value.canonicalKey] ?? Aggregate(
            lemma: lexicalItemID.lemma,
            partOfSpeech: lexicalItemID.partOfSpeech,
            weight: 0
        )
        aggregate.weight += value.occurrenceCount
        byKey[value.canonicalKey] = aggregate
    }
    return byKey.map { key, value in
        candidate(key: key, lemma: value.lemma, pos: value.partOfSpeech, weight: value.weight)
    }
}

private func consequence(
    languageCode: String,
    evaluationSplit: String? = nil,
    cases: [Case],
    results: [CaseResult]
) -> LanguageConsequence {
    let paired = zip(cases, results).filter {
        $0.0.languageCode == languageCode
            && (evaluationSplit == nil || $0.1.evaluationSplit == evaluationSplit)
    }
    let gold = aggregateCandidates(paired.compactMap { item -> DocumentVocabularyCandidate? in
        guard !item.1.expectedExcluded else { return nil }
        let pos = expectedPOS(item.0.goldUPOS)
        let id = VocabularyLexicalItemID(language: languageCode, lemma: item.0.goldLemma, partOfSpeech: pos)
        return candidate(key: id.canonicalKey, lemma: item.0.goldLemma, pos: pos, weight: item.0.occurrenceWeight)
    })
    let predicted = aggregateCandidates(paired.compactMap { item -> DocumentVocabularyCandidate? in
        guard !item.1.predictedExcluded, let lemma = item.1.predictedLemma,
              let pos = VocabularyPartOfSpeech(rawValue: item.1.predictedPartOfSpeech) else { return nil }
        let id = VocabularyLexicalItemID(language: languageCode, lemma: lemma, partOfSpeech: pos)
        return candidate(key: id.canonicalKey, lemma: lemma, pos: pos, weight: item.0.occurrenceWeight)
    })
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

private func groupMetric(dimension: String, value: String, results: [CaseResult]) -> GroupMetric {
    let count = results.count
    let weight = results.reduce(0) { $0 + $1.occurrenceWeight }
    return GroupMetric(
        dimension: dimension,
        value: value,
        caseCount: count,
        occurrenceWeight: weight,
        rawTagAccuracy: Double(results.filter(\.rawTagCorrect).count) / Double(count),
        abstentionRate: Double(results.filter(\.abstained).count) / Double(count),
        finalIdentityAccuracy: Double(results.filter(\.finalIdentityCorrect).count) / Double(count),
        occurrenceWeightedFinalIdentityAccuracy: Double(
            results.filter(\.finalIdentityCorrect).reduce(0) { $0 + $1.occurrenceWeight }
        ) / Double(weight)
    )
}

private func groupedMetrics(_ results: [CaseResult]) -> [GroupMetric] {
    let dimensions: [(String, (CaseResult) -> String)] = [
        ("evaluationSplit", { $0.evaluationSplit }),
        ("language", { $0.languageCode }),
        ("languageAndSplit", { "\($0.languageCode):\($0.evaluationSplit)" }),
        ("genre", { $0.genre }),
        ("expectedPartOfSpeech", { $0.expectedPartOfSpeech }),
        ("languageSplitAndExpectedPartOfSpeech", {
            "\($0.languageCode):\($0.evaluationSplit):\($0.expectedPartOfSpeech)"
        }),
        ("participle", { $0.isParticiple ? "participle" : "other" })
    ]
    return dimensions.flatMap { dimension, key in
        Dictionary(grouping: results, by: key).keys.sorted().map { value in
            groupMetric(
                dimension: dimension,
                value: value,
                results: results.filter { key($0) == value }
            )
        }
    }
}

private func splitMergeSummaries(_ results: [CaseResult]) -> [SplitMergeSummary] {
    let cells = Set(results.map { "\($0.evaluationSplit)|\($0.languageCode)" })
    return cells.sorted().map { cell in
        let parts = cell.split(separator: "|", maxSplits: 1).map(String.init)
        let rows = results.filter { $0.evaluationSplit == parts[0] && $0.languageCode == parts[1] }
        let gold = Set(rows.filter { !$0.expectedExcluded }.map {
            "\($0.languageCode)|\($0.goldLemma)|\($0.expectedPartOfSpeech)"
        })
        let predicted = Set(rows.compactMap { row -> String? in
            guard !row.predictedExcluded, let lemma = row.predictedLemma else { return nil }
            return "\(row.languageCode)|\(lemma)|\(row.predictedPartOfSpeech)"
        })
        func partsByLemma(_ identities: Set<String>) -> [String: Set<String>] {
            Dictionary(grouping: identities) { identity in
                identity.split(separator: "|", maxSplits: 2).dropLast().joined(separator: "|")
            }.mapValues { Set($0.compactMap { $0.split(separator: "|").last.map(String.init) }) }
        }
        let goldByLemma = partsByLemma(gold)
        let predictedByLemma = partsByLemma(predicted)
        let lemmas = Set(goldByLemma.keys).union(predictedByLemma.keys)
        return SplitMergeSummary(
            evaluationSplit: parts[0],
            languageCode: parts[1],
            goldIdentityCount: gold.count,
            predictedIdentityCount: predicted.count,
            missingGoldIdentityCount: gold.subtracting(predicted).count,
            extraPredictedIdentityCount: predicted.subtracting(gold).count,
            lemmaPOSSetMismatchCount: lemmas.filter { goldByLemma[$0, default: []] != predictedByLemma[$0, default: []] }.count
        )
    }
}

@main
private enum VocabularyPOSEvaluator {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: evaluate-vocabulary-pos-fixtures <fixture.json> <report.json>\n", stderr)
            exit(2)
        }
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixture: Fixture
        do {
            fixture = try JSONDecoder().decode(
                Fixture.self,
                from: fixtureData
            )
        } catch {
            fputs("POS fixture decode failed: \(error)\n", stderr)
            throw error
        }
        guard fixture.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        var results: [CaseResult] = []
        for item in fixture.cases {
            let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
            tagger.string = item.text
            guard let range = item.text.range(of: item.surface) else {
                fputs("POS fixture surface not found: \(item.caseID) surface=\(item.surface)\n", stderr)
                throw CocoaError(.coderReadCorrupt)
            }
            let hypotheses = tagger.tagHypotheses(at: range.lowerBound, unit: .word, scheme: .lexicalClass, maximumCount: 2).0
            let ordered = hypotheses.sorted { $0.value > $1.value }
            let predictedPOS = VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: hypotheses)
            let index = VocabularyDocumentLemmaIndex(texts: [item.text], language: language(item.languageCode), maximumWorkerCount: 1)
            let summary = index?.lemmaSummaries().first { summary in
                summary.observedForms.contains { $0.surface.caseInsensitiveCompare(item.surface) == .orderedSame }
            }
            let expected = expectedPOS(item.goldUPOS)
            let expectedExcluded = !assessable(
                lemma: item.goldLemma,
                partOfSpeech: expected,
                languageCode: item.languageCode,
                isConfidentName: item.goldUPOS == "PROPN"
            )
            let predictedExcluded = summary.map {
                !assessable(
                    lemma: $0.displayLemma,
                    partOfSpeech: $0.partOfSpeech,
                    languageCode: item.languageCode,
                    isConfidentName: $0.isConfidentName
                )
            } ?? true
            let predictedLemma = summary?.lemmaKey
            results.append(CaseResult(
                caseID: item.caseID,
                sourceID: item.sourceID,
                languageCode: item.languageCode,
                evaluationSplit: item.evaluationSplit ?? "adversarial",
                genre: item.genre ?? "adversarial",
                isParticiple: item.isParticiple ?? item.goldFeatures.contains("VerbForm=Part"),
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
            fixtureID: fixture.fixtureID,
            fixtureSHA256: SHA256.hash(data: fixtureData).map { String(format: "%02x", $0) }.joined(),
            fixtureRelease: fixture.release,
            environment: ["os": ProcessInfo.processInfo.operatingSystemVersionString],
            policy: ["minimumLeadingProbability": VocabularyPartOfSpeechConfidencePolicy.minimumLeadingProbability, "minimumMargin": VocabularyPartOfSpeechConfidencePolicy.minimumMargin],
            caseResults: results,
            rawTagAccuracy: Double(results.filter(\.rawTagCorrect).count) / Double(results.count),
            abstentionRate: Double(results.filter(\.abstained).count) / Double(results.count),
            finalIdentityAccuracy: Double(results.filter(\.finalIdentityCorrect).count) / Double(results.count),
            occurrenceWeightedFinalIdentityAccuracy: Double(results.filter(\.finalIdentityCorrect).reduce(0) { $0 + $1.occurrenceWeight }) / Double(totalWeight),
            confusion: Dictionary(grouping: results, by: { "\($0.expectedPartOfSpeech)->\($0.predictedPartOfSpeech)" }).mapValues(\.count),
            groupMetrics: groupedMetrics(results),
            splitMergeSummaries: splitMergeSummaries(results),
            consequences: ["en", "de"].map { consequence(languageCode: $0, cases: fixture.cases, results: results) },
            splitConsequences: Set(results.map(\.evaluationSplit)).sorted().flatMap { split in
                ["en", "de"].map {
                    SplitConsequence(
                        evaluationSplit: split,
                        consequence: consequence(
                            languageCode: $0,
                            evaluationSplit: split,
                            cases: fixture.cases,
                            results: results
                        )
                    )
                }
            },
            limitations: fixture.cases.contains(where: { $0.evaluationSplit != nil })
                ? [
                    "The development and held-out UD samples are larger engineering evidence, not real LeafReader document or learner validation.",
                    "German GSD supplies one mixed-web source stratum and upstream lemmas have known provenance limits; results do not establish sense correctness.",
                    "NaturalLanguage behavior is OS-dependent and must be rerun after relevant macOS changes."
                ]
                : [
                    "Eight selected UD tokens are adversarial engineering fixtures, not a representative POS accuracy estimate.",
                    "German GSD lemmas are upstream annotations with known provenance limits; final identity results do not establish sense correctness.",
                    "NaturalLanguage behavior is OS-dependent and must be rerun after relevant macOS changes."
                ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }
}
