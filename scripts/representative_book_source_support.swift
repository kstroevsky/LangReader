import Foundation
import LeafReaderCore
import PDFKit

enum RepresentativeBookSourceError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message): message
        }
    }
}

struct RepresentativeBookSampledSource {
    let documentFormat: String
    let sourceUnitKind: String
    let sourceUnitCount: Int
    let sampledUnitNumbers: [Int]
    let sampledTexts: [String]
}

enum RepresentativeBookSourceSupport {
    static let epubChunkCharacterLimit = 8_000

    static func sampledUnitIndexes(unitCount: Int, requestedCount: Int) -> [Int] {
        guard unitCount > 0, requestedCount > 0 else { return [] }
        let count = min(unitCount, requestedCount)
        let start = unitCount >= 20 ? Int((Double(unitCount - 1) * 0.05).rounded()) : 0
        let end = unitCount >= 20 ? Int((Double(unitCount - 1) * 0.95).rounded()) : unitCount - 1
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

    static func sample(sourceURL: URL, requestedCount: Int) throws -> RepresentativeBookSampledSource {
        switch sourceURL.pathExtension.lowercased() {
        case "pdf":
            return try samplePDF(sourceURL, requestedCount: requestedCount)
        case "epub":
            return try sampleEPUB(sourceURL, requestedCount: requestedCount)
        default:
            throw RepresentativeBookSourceError.invalid(
                "representative-book source must be PDF or EPUB: \(sourceURL.lastPathComponent)"
            )
        }
    }

    static func texts(
        sourceURL: URL,
        sourceUnitKind: String,
        sourceUnitCount: Int,
        unitNumbers: [Int]
    ) throws -> [String] {
        switch sourceURL.pathExtension.lowercased() {
        case "pdf":
            guard sourceUnitKind == "pdf-page",
                  let document = PDFDocument(url: sourceURL),
                  document.pageCount == sourceUnitCount else {
                throw RepresentativeBookSourceError.invalid("PDF source units do not match annotation provenance")
            }
            return try unitNumbers.map { number in
                guard number >= 1,
                      number <= document.pageCount,
                      let text = document.page(at: number - 1)?.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RepresentativeBookSourceError.invalid(
                        "sampled PDF page \(number) is unavailable or has no text"
                    )
                }
                return text
            }
        case "epub":
            guard sourceUnitKind == "epub-paragraph-pack-v1" else {
                throw RepresentativeBookSourceError.invalid("EPUB source-unit policy changed")
            }
            let document = try WebDocumentLoader.load(url: sourceURL)
            let plainText = document.plainTextLoader?() ?? document.plainText
            let units = epubTextUnits(plainText)
            guard units.count == sourceUnitCount else {
                throw RepresentativeBookSourceError.invalid("EPUB source units do not match annotation provenance")
            }
            return try unitNumbers.map { number in
                guard number >= 1, number <= units.count else {
                    throw RepresentativeBookSourceError.invalid("sampled EPUB unit \(number) is unavailable")
                }
                return units[number - 1]
            }
        default:
            throw RepresentativeBookSourceError.invalid(
                "representative-book source must be PDF or EPUB: \(sourceURL.lastPathComponent)"
            )
        }
    }

    static func epubTextUnits(_ text: String, characterLimit: Int = epubChunkCharacterLimit) -> [String] {
        guard characterLimit > 0 else { return [] }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var units: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            units.append(current)
            current = ""
        }

        for paragraph in paragraphs {
            var remainder = paragraph
            while remainder.count > characterLimit {
                flush()
                let split = remainder.index(remainder.startIndex, offsetBy: characterLimit)
                units.append(String(remainder[..<split]))
                remainder = String(remainder[split...])
            }
            guard !remainder.isEmpty else { continue }
            let separatorCount = current.isEmpty ? 0 : 1
            if current.count + separatorCount + remainder.count > characterLimit {
                flush()
            }
            current += current.isEmpty ? remainder : "\n\(remainder)"
        }
        flush()
        return units
    }

    static func sampledReadablePDFPages(
        _ pageTexts: [String?],
        requestedCount: Int
    ) -> [(number: Int, text: String)] {
        let readable = pageTexts.enumerated().compactMap { index, text -> (number: Int, text: String)? in
            guard let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (index + 1, text)
        }
        let indexes = sampledUnitIndexes(unitCount: readable.count, requestedCount: requestedCount)
        return indexes.map { readable[$0] }
    }

    private static func samplePDF(
        _ sourceURL: URL,
        requestedCount: Int
    ) throws -> RepresentativeBookSampledSource {
        guard let document = PDFDocument(url: sourceURL), document.pageCount > 0 else {
            throw RepresentativeBookSourceError.invalid("PDFKit could not open the document")
        }
        let pageTexts = (0..<document.pageCount).map { document.page(at: $0)?.string }
        let sampledPages = sampledReadablePDFPages(pageTexts, requestedCount: requestedCount)
        guard !sampledPages.isEmpty else {
            throw RepresentativeBookSourceError.invalid("PDFKit extracted no readable text from the document")
        }
        return RepresentativeBookSampledSource(
            documentFormat: "pdf",
            sourceUnitKind: "pdf-page",
            sourceUnitCount: document.pageCount,
            sampledUnitNumbers: sampledPages.map(\.number),
            sampledTexts: sampledPages.map(\.text)
        )
    }

    private static func sampleEPUB(
        _ sourceURL: URL,
        requestedCount: Int
    ) throws -> RepresentativeBookSampledSource {
        let document = try WebDocumentLoader.load(url: sourceURL)
        let plainText = document.plainTextLoader?() ?? document.plainText
        let units = epubTextUnits(plainText)
        guard !units.isEmpty else {
            throw RepresentativeBookSourceError.invalid("LeafReader extracted no readable EPUB text")
        }
        let indexes = sampledUnitIndexes(unitCount: units.count, requestedCount: requestedCount)
        return RepresentativeBookSampledSource(
            documentFormat: "epub",
            sourceUnitKind: "epub-paragraph-pack-v1",
            sourceUnitCount: units.count,
            sampledUnitNumbers: indexes.map { $0 + 1 },
            sampledTexts: indexes.map { units[$0] }
        )
    }
}
