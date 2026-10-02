import CryptoKit
import Foundation
import LeafReaderCore
import NaturalLanguage

private let challengePolicyVersion = "representative-book-challenge-v3"
private let representativePolicyVersion = "representative-book-representative-v2"

private enum CandidatePanel: String, Codable {
    case challenge
    case representative
}

private struct SourceDescriptor: Codable {
    let alias: String
    let fileName: String
    let sourceSHA256: String
    let languageCode: String
    let genre: String
    let documentFormat: String
    let dataRole: String
    let sourceUnitKind: String
    let sourceUnitCount: Int
    let sampledUnitNumbers: [Int]
    let sampledCharacterCount: Int
    let sampledTokenCount: Int
}

private struct CandidateOccurrence: Codable {
    let occurrenceID: String
    let sourceUnitNumber: Int
    let sampledUnitIndex: Int
    let utf16Location: Int
    let utf16Length: Int
    let surface: String
    let observedLemma: String?
    let observedPartOfSpeech: String?
    let context: String
    let contextFingerprint: String
    let goldLemma: String
    let goldPartOfSpeech: String
    let reviewStatus: String
}

private struct CandidateAnchor: Codable {
    let anchorID: String
    let anchorBasis: String
    let anchorValue: String
    let occurrenceCountInSample: Int
    let distinctUnitCount: Int
    let observedPartsOfSpeech: [String]
    let capitalizationPatterns: [String]
    let priorityScore: Int?
    let occurrences: [CandidateOccurrence]
}

private struct AnnotationTemplate: Codable {
    let schemaVersion: Int
    let panel: CandidatePanel
    let candidateSelectionPolicyVersion: String
    let sampledTextSHA256: String
    let source: SourceDescriptor
    let instructions: [String]
    let anchors: [CandidateAnchor]
}

private struct SafeMetadata: Codable {
    let schemaVersion: Int
    let panel: CandidatePanel
    let candidateSelectionPolicyVersion: String
    let source: SourceDescriptor
    let candidateAnchorCount: Int
    let candidateOccurrenceCount: Int
    let predictedMultiPOSAnchorCount: Int?
    let otherWordAnchorCount: Int?
    let sampledTextSHA256: String
    let containsExtractedProse: Bool
}

private struct RawOccurrence {
    let sourceUnitNumber: Int
    let sampledUnitIndex: Int
    let ordinal: Int
    let utf16Location: Int
    let utf16Length: Int
    let surface: String
    let lemma: String?
    let partOfSpeech: String?
    let context: String
}

private enum ToolError: Error, CustomStringConvertible {
    case usage
    case invalid(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: build_vocabulary_representative_book_candidates.swift --source <book.pdf|book.epub> --language <bcp47> --alias <id> --genre <genre> --template <local.json> --metadata <safe.json> [--panel challenge|representative] [--data-role development|confirmatory] [--sample-units <n>] [--max-anchors <n>] [--max-occurrences <n>] | --self-test"
        case .invalid(let message):
            return message
        }
    }
}

private struct Options {
    let source: URL
    let languageCode: String
    let alias: String
    let genre: String
    let template: URL
    let metadata: URL
    let panel: CandidatePanel
    let dataRole: String
    let sampleUnits: Int
    let maxAnchors: Int
    let maxOccurrences: Int
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func canonicalToken(_ value: String) -> String? {
    let normalized = value.precomposedStringWithCanonicalMapping
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard normalized.count >= 2,
          normalized.range(
            of: #"^[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*$"#,
            options: .regularExpression
          ) != nil else {
        return nil
    }
    return normalized
}

private func compactContext(_ text: String, around range: Range<String.Index>) -> String {
    let lower = text.index(range.lowerBound, offsetBy: -90, limitedBy: text.startIndex) ?? text.startIndex
    let upper = text.index(range.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
    return text[lower..<upper]
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

private func capitalizationPattern(_ surface: String) -> String {
    let letters = surface.filter(\.isLetter)
    guard !letters.isEmpty else { return "none" }
    if letters == letters.uppercased() { return "uppercase" }
    if letters == letters.lowercased() { return "lowercase" }
    if letters.first?.isUppercase == true && letters.dropFirst().allSatisfy(\.isLowercase) {
        return "initial-uppercase"
    }
    return "mixed"
}

private func lexicalClassName(_ tag: NLTag?) -> String? {
    switch tag {
    case .noun: return "noun"
    case .verb: return "verb"
    case .adjective: return "adjective"
    case .adverb: return "adverb"
    case .otherWord: return "otherWord"
    default: return nil
    }
}

private func rawOccurrences(
    sourceUnitNumber: Int,
    sampledUnitIndex: Int,
    text: String,
    language: NLLanguage,
    observeLinguistics: Bool
) -> [RawOccurrence] {
    let tagger: NLTagger? = observeLinguistics ? NLTagger(tagSchemes: [.lemma, .lexicalClass]) : nil
    tagger?.string = text
    tagger?.setLanguage(language, range: text.startIndex..<text.endIndex)

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    tokenizer.setLanguage(language)

    var result: [RawOccurrence] = []
    var ordinal = 0
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        defer { ordinal += 1 }
        let surface = String(text[range])
        guard canonicalToken(surface) != nil else { return true }

        let lemma: String?
        let lexicalClass: String?
        if let tagger {
            let rawLemma = tagger.tag(
                at: range.lowerBound,
                unit: .word,
                scheme: .lemma
            ).0?.rawValue
            lemma = rawLemma.flatMap(canonicalToken)
            lexicalClass = lexicalClassName(
                tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            )
        } else {
            lemma = nil
            lexicalClass = nil
        }

        let utf16Range = NSRange(range, in: text)
        result.append(RawOccurrence(
            sourceUnitNumber: sourceUnitNumber,
            sampledUnitIndex: sampledUnitIndex,
            ordinal: ordinal,
            utf16Location: utf16Range.location,
            utf16Length: utf16Range.length,
            surface: surface,
            lemma: lemma,
            partOfSpeech: lexicalClass,
            context: compactContext(text, around: range)
        ))
        return true
    }
    return result
}

private func representativeOrderKey(alias: String, anchor: String, row: RawOccurrence? = nil) -> String {
    var value = "\(alias)|\(anchor)"
    if let row {
        value += "|\(row.sourceUnitNumber)|\(row.ordinal)"
    }
    return sha256(Data(value.utf8))
}

private func candidateAnchors(
    occurrences: [RawOccurrence],
    alias: String,
    panel: CandidatePanel,
    maxAnchors: Int,
    maxOccurrences: Int
) -> [CandidateAnchor] {
    let grouped = Dictionary(grouping: occurrences) { occurrence in
        switch panel {
        case .challenge:
            occurrence.lemma ?? canonicalToken(occurrence.surface) ?? ""
        case .representative:
            canonicalToken(occurrence.surface) ?? ""
        }
    }

    let candidates = grouped.compactMap { key, rows -> CandidateAnchor? in
        guard !key.isEmpty, rows.count >= 2 else { return nil }
        let parts = Set(rows.compactMap(\.partOfSpeech))
        if panel == .challenge, parts.isEmpty { return nil }
        let units = Set(rows.map(\.sourceUnitNumber))
        let capitalization = Set(rows.map { capitalizationPattern($0.surface) })
        let contentParts = parts.intersection(["noun", "verb", "adjective", "adverb"])
        let hasOtherWord = parts.contains("otherWord")
        let priority: Int? = panel == .challenge
            ? (contentParts.count >= 2 ? 10_000 : 0)
                + (hasOtherWord ? 2_000 : 0)
                + (capitalization.count >= 2 ? 1_000 : 0)
                + min(rows.count, 99) * 10
                + min(units.count, 9)
            : nil

        let orderedRows = rows.sorted {
            if panel == .representative {
                let lhs = representativeOrderKey(alias: alias, anchor: key, row: $0)
                let rhs = representativeOrderKey(alias: alias, anchor: key, row: $1)
                if lhs != rhs { return lhs < rhs }
            }
            if $0.sourceUnitNumber != $1.sourceUnitNumber {
                return $0.sourceUnitNumber < $1.sourceUnitNumber
            }
            return $0.ordinal < $1.ordinal
        }
        let selected = orderedRows.prefix(maxOccurrences).map { row in
            CandidateOccurrence(
                occurrenceID: "\(alias)-u\(row.sourceUnitNumber)-t\(row.ordinal)",
                sourceUnitNumber: row.sourceUnitNumber,
                sampledUnitIndex: row.sampledUnitIndex,
                utf16Location: row.utf16Location,
                utf16Length: row.utf16Length,
                surface: row.surface,
                observedLemma: row.lemma,
                observedPartOfSpeech: row.partOfSpeech,
                context: row.context,
                contextFingerprint: sha256(Data(row.context.utf8)),
                goldLemma: "",
                goldPartOfSpeech: "",
                reviewStatus: "unreviewed"
            )
        }

        return CandidateAnchor(
            anchorID: "\(alias)-\(key)",
            anchorBasis: panel == .challenge ? "observedLemma" : "canonicalSurface",
            anchorValue: key,
            occurrenceCountInSample: rows.count,
            distinctUnitCount: units.count,
            observedPartsOfSpeech: parts.sorted(),
            capitalizationPatterns: capitalization.sorted(),
            priorityScore: priority,
            occurrences: Array(selected)
        )
    }

    let ordered = candidates.sorted {
        if panel == .representative {
            let lhs = representativeOrderKey(alias: alias, anchor: $0.anchorValue)
            let rhs = representativeOrderKey(alias: alias, anchor: $1.anchorValue)
            if lhs != rhs { return lhs < rhs }
            return $0.anchorValue < $1.anchorValue
        }
        let lhsPriority = $0.priorityScore ?? 0
        let rhsPriority = $1.priorityScore ?? 0
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
        if $0.occurrenceCountInSample != $1.occurrenceCountInSample {
            return $0.occurrenceCountInSample > $1.occurrenceCountInSample
        }
        return $0.anchorValue < $1.anchorValue
    }
    return Array(ordered.prefix(maxAnchors))
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--"), index + 1 < arguments.count else { throw ToolError.usage }
        values[key] = arguments[index + 1]
        index += 2
    }

    guard let source = values["--source"] ?? values["--pdf"],
          let language = values["--language"],
          let alias = values["--alias"],
          let genre = values["--genre"],
          let template = values["--template"],
          let metadata = values["--metadata"] else {
        throw ToolError.usage
    }
    guard let panel = CandidatePanel(rawValue: values["--panel"] ?? "challenge") else {
        throw ToolError.invalid("panel must be challenge or representative")
    }
    let dataRole = values["--data-role"] ?? "development"
    guard dataRole == "development" || dataRole == "confirmatory" else {
        throw ToolError.invalid("data-role must be development or confirmatory")
    }
    guard panel != .challenge || dataRole == "development" else {
        throw ToolError.invalid("prediction-guided challenge selection is development-only")
    }

    let sampleUnits = Int(values["--sample-units"] ?? values["--sample-pages"] ?? "32") ?? 0
    let maxAnchors = Int(values["--max-anchors"] ?? "80") ?? 0
    let maxOccurrences = Int(values["--max-occurrences"] ?? "12") ?? 0
    guard sampleUnits > 0, maxAnchors > 0, maxOccurrences > 0 else {
        throw ToolError.invalid("sample-units, max-anchors, and max-occurrences must be positive")
    }
    guard !alias.isEmpty,
          alias.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }) else {
        throw ToolError.invalid("alias must use lowercase letters, numbers, and hyphens")
    }
    guard VocabularyLanguageID(language) != nil else {
        throw ToolError.invalid("language must be a resolved BCP-47 identity")
    }

    return Options(
        source: URL(fileURLWithPath: source),
        languageCode: language,
        alias: alias,
        genre: genre,
        template: URL(fileURLWithPath: template),
        metadata: URL(fileURLWithPath: metadata),
        panel: panel,
        dataRole: dataRole,
        sampleUnits: sampleUnits,
        maxAnchors: maxAnchors,
        maxOccurrences: maxOccurrences
    )
}

private func build(_ options: Options) throws {
    guard FileManager.default.fileExists(atPath: options.source.path) else {
        throw ToolError.invalid("source does not exist: \(options.source.path)")
    }

    let sample = try RepresentativeBookSourceSupport.sample(
        sourceURL: options.source,
        requestedCount: options.sampleUnits
    )
    let language = NLLanguage(rawValue: options.languageCode)
    var occurrences: [RawOccurrence] = []
    for (sampledUnitIndex, text) in sample.sampledTexts.enumerated() {
        occurrences.append(contentsOf: rawOccurrences(
            sourceUnitNumber: sample.sampledUnitNumbers[sampledUnitIndex],
            sampledUnitIndex: sampledUnitIndex,
            text: text,
            language: language,
            observeLinguistics: options.panel == .challenge
        ))
    }
    let anchors = candidateAnchors(
        occurrences: occurrences,
        alias: options.alias,
        panel: options.panel,
        maxAnchors: options.maxAnchors,
        maxOccurrences: options.maxOccurrences
    )
    guard !anchors.isEmpty else {
        throw ToolError.invalid("no repeated lexical candidates were found")
    }

    let sourceData = try Data(contentsOf: options.source)
    let sampledText = sample.sampledTexts.joined(separator: "\n\u{001E}\n")
    let sampledTextSHA256 = sha256(Data(sampledText.utf8))
    let policyVersion = options.panel == .challenge ? challengePolicyVersion : representativePolicyVersion
    let source = SourceDescriptor(
        alias: options.alias,
        fileName: options.source.lastPathComponent,
        sourceSHA256: sha256(sourceData),
        languageCode: options.languageCode,
        genre: options.genre,
        documentFormat: sample.documentFormat,
        dataRole: options.dataRole,
        sourceUnitKind: sample.sourceUnitKind,
        sourceUnitCount: sample.sourceUnitCount,
        sampledUnitNumbers: sample.sampledUnitNumbers,
        sampledCharacterCount: sample.sampledTexts.reduce(0) { $0 + $1.count },
        sampledTokenCount: occurrences.count
    )
    let template = AnnotationTemplate(
        schemaVersion: 2,
        panel: options.panel,
        candidateSelectionPolicyVersion: policyVersion,
        sampledTextSHA256: sampledTextSHA256,
        source: source,
        instructions: [
            options.dataRole == "development"
                ? "Development material only. Do not convert this source into fresh holdout evidence after inspecting predictions."
                : "Confirmatory source. Freeze human gold before running or revealing A/B/C predictions.",
            options.panel == .challenge
                ? "Observed NaturalLanguage values exist only to prioritize development failures; never copy them into gold."
                : "Selection is prediction-independent. Annotators must remain blind to A/B/C predictions while filling gold lemma and coarse POS.",
            "Review every retained occurrence in context and reject extraction/alignment errors instead of forcing a lexical label.",
            "Only occurrences marked approved may be materialized into the lexical-partition evaluator schema."
        ],
        anchors: anchors
    )
    let metadata = SafeMetadata(
        schemaVersion: 2,
        panel: options.panel,
        candidateSelectionPolicyVersion: policyVersion,
        source: source,
        candidateAnchorCount: anchors.count,
        candidateOccurrenceCount: anchors.reduce(0) { $0 + $1.occurrences.count },
        predictedMultiPOSAnchorCount: options.panel == .challenge ? anchors.filter {
            Set($0.observedPartsOfSpeech).intersection(["noun", "verb", "adjective", "adverb"]).count >= 2
        }.count : nil,
        otherWordAnchorCount: options.panel == .challenge
            ? anchors.filter { $0.observedPartsOfSpeech.contains("otherWord") }.count
            : nil,
        sampledTextSHA256: sampledTextSHA256,
        containsExtractedProse: false
    )

    try writeJSON(template, to: options.template)
    try writeJSON(metadata, to: options.metadata)
    print("wrote \(anchors.count) \(options.panel.rawValue) anchors / \(metadata.candidateOccurrenceCount) review occurrences")
    print("annotation template: \(options.template.path)")
    print("safe metadata: \(options.metadata.path)")
}

private func selfTest() throws {
    let sample = RepresentativeBookSourceSupport.sampledUnitIndexes(unitCount: 213, requestedCount: 5)
    guard sample == [11, 59, 106, 154, 201] else {
        throw ToolError.invalid("unit sampling changed: \(sample)")
    }
    guard canonicalToken("Record") == "record",
          canonicalToken("Fußgänger") == "fußgänger",
          canonicalToken("don't") == "don't",
          canonicalToken("123") == nil else {
        throw ToolError.invalid("canonical token policy changed")
    }
    guard capitalizationPattern("Haus") == "initial-uppercase",
          capitalizationPattern("HOUSE") == "uppercase",
          capitalizationPattern("house") == "lowercase" else {
        throw ToolError.invalid("capitalization policy changed")
    }
    let chunks = RepresentativeBookSourceSupport.epubTextUnits(
        "First paragraph.\n\nSecond paragraph.",
        characterLimit: 20
    )
    guard chunks == ["First paragraph.", "Second paragraph."] else {
        throw ToolError.invalid("EPUB paragraph packing changed: \(chunks)")
    }
    let readablePDFPages = RepresentativeBookSourceSupport.sampledReadablePDFPages(
        ["cover", "   ", nil, "middle", "", "ending"],
        requestedCount: 3
    )
    guard readablePDFPages.map(\.number) == [1, 4, 6],
          readablePDFPages.map(\.text) == ["cover", "middle", "ending"] else {
        throw ToolError.invalid("readable PDF page sampling changed")
    }
    let representativeRows = [
        RawOccurrence(
            sourceUnitNumber: 1,
            sampledUnitIndex: 0,
            ordinal: 0,
            utf16Location: 0,
            utf16Length: 6,
            surface: "Record",
            lemma: nil,
            partOfSpeech: nil,
            context: "Record this."
        ),
        RawOccurrence(
            sourceUnitNumber: 2,
            sampledUnitIndex: 1,
            ordinal: 0,
            utf16Location: 0,
            utf16Length: 6,
            surface: "record",
            lemma: nil,
            partOfSpeech: nil,
            context: "A record."
        )
    ]
    let representative = candidateAnchors(
        occurrences: representativeRows,
        alias: "self-test",
        panel: .representative,
        maxAnchors: 10,
        maxOccurrences: 10
    )
    guard representative.count == 1,
          representative[0].anchorBasis == "canonicalSurface",
          representative[0].observedPartsOfSpeech.isEmpty,
          representative[0].priorityScore == nil else {
        throw ToolError.invalid("representative selection depends on prediction fields")
    }
    print("representative book candidate builder self-test passed")
}

@main
private enum RepresentativeBookCandidateBuilderCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--self-test"] {
                try selfTest()
            } else {
                try build(parseOptions(arguments))
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }
}
