#!/usr/bin/env swift

import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

private let policyVersion = "representative-book-candidate-v1"

private struct SourceDescriptor: Codable {
    let alias: String
    let fileName: String
    let sourceSHA256: String
    let languageCode: String
    let genre: String
    let documentFormat: String
    let dataRole: String
    let pageCount: Int
    let sampledPageNumbers: [Int]
    let sampledCharacterCount: Int
    let sampledTokenCount: Int
}

private struct CandidateOccurrence: Codable {
    let occurrenceID: String
    let pageNumber: Int
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
    let suggestedLemma: String
    let occurrenceCountInSample: Int
    let distinctPageCount: Int
    let observedPartsOfSpeech: [String]
    let capitalizationPatterns: [String]
    let priorityScore: Int
    let occurrences: [CandidateOccurrence]
}

private struct AnnotationTemplate: Codable {
    let schemaVersion: Int
    let candidateSelectionPolicyVersion: String
    let sampledTextSHA256: String
    let source: SourceDescriptor
    let instructions: [String]
    let anchors: [CandidateAnchor]
}

private struct SafeMetadata: Codable {
    let schemaVersion: Int
    let candidateSelectionPolicyVersion: String
    let source: SourceDescriptor
    let candidateAnchorCount: Int
    let candidateOccurrenceCount: Int
    let predictedMultiPOSAnchorCount: Int
    let otherWordAnchorCount: Int
    let sampledTextSHA256: String
    let containsExtractedProse: Bool
}

private struct RawOccurrence {
    let pageNumber: Int
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
            return "usage: build_vocabulary_representative_book_candidates.swift --pdf <file.pdf> --language <bcp47> --alias <id> --genre <genre> --template <local.json> --metadata <safe.json> [--sample-pages <n>] [--max-anchors <n>] [--max-occurrences <n>] | --self-test"
        case .invalid(let message):
            return message
        }
    }
}

private struct Options {
    let pdf: URL
    let languageCode: String
    let alias: String
    let genre: String
    let template: URL
    let metadata: URL
    let samplePages: Int
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

private func sampledPageIndexes(pageCount: Int, requestedCount: Int) -> [Int] {
    guard pageCount > 0, requestedCount > 0 else { return [] }
    let count = min(pageCount, requestedCount)
    let start = pageCount >= 20 ? Int((Double(pageCount - 1) * 0.05).rounded()) : 0
    let end = pageCount >= 20 ? Int((Double(pageCount - 1) * 0.95).rounded()) : pageCount - 1
    guard count > 1, end > start else { return [(start + end) / 2] }

    let span = Double(end - start)
    var result: [Int] = []
    var seen = Set<Int>()
    for ordinal in 0..<count {
        let fraction = Double(ordinal) / Double(count - 1)
        let index = start + Int((span * fraction).rounded())
        if seen.insert(index).inserted {
            result.append(index)
        }
    }
    return result
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
    pageNumber: Int,
    sampledUnitIndex: Int,
    text: String,
    language: NLLanguage
) -> [RawOccurrence] {
    let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
    tagger.string = text
    tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    tokenizer.setLanguage(language)

    var result: [RawOccurrence] = []
    var ordinal = 0
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        defer { ordinal += 1 }
        let surface = String(text[range])
        guard canonicalToken(surface) != nil else { return true }
        let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
        let lexicalClass = lexicalClassName(
            tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
        )
        let utf16Range = NSRange(range, in: text)
        result.append(RawOccurrence(
            pageNumber: pageNumber,
            sampledUnitIndex: sampledUnitIndex,
            ordinal: ordinal,
            utf16Location: utf16Range.location,
            utf16Length: utf16Range.length,
            surface: surface,
            lemma: lemmaTag.flatMap(canonicalToken),
            partOfSpeech: lexicalClass,
            context: compactContext(text, around: range)
        ))
        return true
    }
    return result
}

private func candidateAnchors(
    occurrences: [RawOccurrence],
    alias: String,
    maxAnchors: Int,
    maxOccurrences: Int
) -> [CandidateAnchor] {
    let grouped = Dictionary(grouping: occurrences) { occurrence in
        occurrence.lemma ?? canonicalToken(occurrence.surface) ?? ""
    }

    return grouped.compactMap { key, rows -> CandidateAnchor? in
        guard !key.isEmpty, rows.count >= 2 else { return nil }
        let parts = Set(rows.compactMap(\.partOfSpeech))
        guard !parts.isEmpty else { return nil }
        let pages = Set(rows.map(\.pageNumber))
        let capitalization = Set(rows.map { capitalizationPattern($0.surface) })
        let contentParts = parts.intersection(["noun", "verb", "adjective", "adverb"])
        let hasOtherWord = parts.contains("otherWord")
        let priority = (contentParts.count >= 2 ? 10_000 : 0)
            + (hasOtherWord ? 2_000 : 0)
            + (capitalization.count >= 2 ? 1_000 : 0)
            + min(rows.count, 99) * 10
            + min(pages.count, 9)
        let selected = rows
            .sorted {
                if $0.pageNumber != $1.pageNumber { return $0.pageNumber < $1.pageNumber }
                return $0.ordinal < $1.ordinal
            }
            .prefix(maxOccurrences)
            .map { row in
                CandidateOccurrence(
                    occurrenceID: "\(alias)-p\(row.pageNumber)-t\(row.ordinal)",
                    pageNumber: row.pageNumber,
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
            suggestedLemma: key,
            occurrenceCountInSample: rows.count,
            distinctPageCount: pages.count,
            observedPartsOfSpeech: parts.sorted(),
            capitalizationPatterns: capitalization.sorted(),
            priorityScore: priority,
            occurrences: Array(selected)
        )
    }
    .sorted {
        if $0.priorityScore != $1.priorityScore { return $0.priorityScore > $1.priorityScore }
        if $0.occurrenceCountInSample != $1.occurrenceCountInSample {
            return $0.occurrenceCountInSample > $1.occurrenceCountInSample
        }
        return $0.suggestedLemma < $1.suggestedLemma
    }
    .prefix(maxAnchors)
    .map { $0 }
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
    guard let pdf = values["--pdf"],
          let language = values["--language"],
          let alias = values["--alias"],
          let genre = values["--genre"],
          let template = values["--template"],
          let metadata = values["--metadata"] else {
        throw ToolError.usage
    }
    let samplePages = Int(values["--sample-pages"] ?? "32") ?? 0
    let maxAnchors = Int(values["--max-anchors"] ?? "80") ?? 0
    let maxOccurrences = Int(values["--max-occurrences"] ?? "12") ?? 0
    guard samplePages > 0, maxAnchors > 0, maxOccurrences > 0 else {
        throw ToolError.invalid("sample-pages, max-anchors, and max-occurrences must be positive")
    }
    guard !alias.isEmpty,
          alias.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }) else {
        throw ToolError.invalid("alias must use lowercase letters, numbers, and hyphens")
    }
    return Options(
        pdf: URL(fileURLWithPath: pdf),
        languageCode: language,
        alias: alias,
        genre: genre,
        template: URL(fileURLWithPath: template),
        metadata: URL(fileURLWithPath: metadata),
        samplePages: samplePages,
        maxAnchors: maxAnchors,
        maxOccurrences: maxOccurrences
    )
}

private func build(_ options: Options) throws {
    guard options.pdf.pathExtension.lowercased() == "pdf" else {
        throw ToolError.invalid("representative book candidate builder currently accepts PDF only")
    }
    guard FileManager.default.fileExists(atPath: options.pdf.path) else {
        throw ToolError.invalid("PDF does not exist: \(options.pdf.path)")
    }
    guard let document = PDFDocument(url: options.pdf), document.pageCount > 0 else {
        throw ToolError.invalid("PDFKit could not open the document")
    }
    let language = NLLanguage(rawValue: options.languageCode)
    let pages = sampledPageIndexes(pageCount: document.pageCount, requestedCount: options.samplePages)
    var occurrences: [RawOccurrence] = []
    var sampledTexts: [String] = []
    var sampledPageNumbers: [Int] = []
    for pageIndex in pages {
        let text = document.page(at: pageIndex)?.string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let sampledUnitIndex = sampledTexts.count
        sampledTexts.append(text)
        sampledPageNumbers.append(pageIndex + 1)
        occurrences.append(contentsOf: rawOccurrences(
            pageNumber: pageIndex + 1,
            sampledUnitIndex: sampledUnitIndex,
            text: text,
            language: language
        ))
    }
    guard !sampledTexts.isEmpty else {
        throw ToolError.invalid("PDFKit extracted no text from the sampled pages")
    }
    let anchors = candidateAnchors(
        occurrences: occurrences,
        alias: options.alias,
        maxAnchors: options.maxAnchors,
        maxOccurrences: options.maxOccurrences
    )
    guard !anchors.isEmpty else {
        throw ToolError.invalid("no repeated lexical candidates were found")
    }
    let sourceData = try Data(contentsOf: options.pdf)
    let sampledText = sampledTexts.joined(separator: "\n\u{001E}\n")
    let sampledTextSHA256 = sha256(Data(sampledText.utf8))
    let source = SourceDescriptor(
        alias: options.alias,
        fileName: options.pdf.lastPathComponent,
        sourceSHA256: sha256(sourceData),
        languageCode: options.languageCode,
        genre: options.genre,
        documentFormat: "pdf",
        dataRole: "development",
        pageCount: document.pageCount,
        sampledPageNumbers: sampledPageNumbers,
        sampledCharacterCount: sampledTexts.reduce(0) { $0 + $1.count },
        sampledTokenCount: occurrences.count
    )
    let template = AnnotationTemplate(
        schemaVersion: 1,
        candidateSelectionPolicyVersion: policyVersion,
        sampledTextSHA256: sampledTextSHA256,
        source: source,
        instructions: [
            "Development material only. Do not convert this source into a held-out fixture after inspecting predictions.",
            "Review every retained occurrence in context; fill goldLemma and goldPartOfSpeech without treating observed NaturalLanguage output as ground truth.",
            "Reject extraction/alignment errors explicitly rather than forcing a lexical label.",
            "After review, transform only approved occurrences into the lexical-partition evaluator schema."
        ],
        anchors: anchors
    )
    let metadata = SafeMetadata(
        schemaVersion: 1,
        candidateSelectionPolicyVersion: policyVersion,
        source: source,
        candidateAnchorCount: anchors.count,
        candidateOccurrenceCount: anchors.reduce(0) { $0 + $1.occurrences.count },
        predictedMultiPOSAnchorCount: anchors.filter {
            Set($0.observedPartsOfSpeech).intersection(["noun", "verb", "adjective", "adverb"]).count >= 2
        }.count,
        otherWordAnchorCount: anchors.filter { $0.observedPartsOfSpeech.contains("otherWord") }.count,
        sampledTextSHA256: sampledTextSHA256,
        containsExtractedProse: false
    )
    try writeJSON(template, to: options.template)
    try writeJSON(metadata, to: options.metadata)
    print("wrote \(anchors.count) candidate anchors / \(metadata.candidateOccurrenceCount) review occurrences")
    print("annotation template: \(options.template.path)")
    print("safe metadata: \(options.metadata.path)")
}

private func selfTest() throws {
    let sample = sampledPageIndexes(pageCount: 213, requestedCount: 5)
    guard sample == [11, 59, 106, 154, 201] else {
        throw ToolError.invalid("page sampling changed: \(sample)")
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
    print("representative book candidate builder self-test passed")
}

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
