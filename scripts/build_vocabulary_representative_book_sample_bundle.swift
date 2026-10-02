import CryptoKit
import Foundation

private struct AnnotationTemplate: Decodable {
    struct Source: Decodable {
        let alias: String
        let sourceSHA256: String
        let languageCode: String
        let documentFormat: String
        let dataRole: String
        let sourceUnitKind: String
        let sourceUnitCount: Int
        let sampledUnitNumbers: [Int]
    }

    let schemaVersion: Int
    let candidateSelectionPolicyVersion: String
    let sampledTextSHA256: String
    let source: Source
}

private struct SampleBundle: Encodable {
    let schemaVersion: Int
    let documentAlias: String
    let sourceSHA256: String
    let annotationSHA256: String
    let candidateSelectionPolicyVersion: String
    let sampledTextSHA256: String
    let languageCode: String
    let documentFormat: String
    let dataRole: String
    let sourceUnitKind: String
    let sourceUnitCount: Int
    let sampledUnitNumbers: [Int]
    let sampledTexts: [String]
    let containsExtractedProse: Bool
}

private enum BundleError: Error, CustomStringConvertible {
    case usage
    case invalid(String)

    var description: String {
        switch self {
        case .usage:
            "usage: build_vocabulary_representative_book_sample_bundle <annotation-v2.json> <source.pdf|source.epub> <bundle.json>"
        case .invalid(let message):
            message
        }
    }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@main
private enum RepresentativeBookSampleBundleCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 3 else { throw BundleError.usage }
            let annotationURL = URL(fileURLWithPath: arguments[0])
            let sourceURL = URL(fileURLWithPath: arguments[1])
            let outputURL = URL(fileURLWithPath: arguments[2])

            let annotationData = try Data(contentsOf: annotationURL)
            let annotation = try JSONDecoder().decode(
                AnnotationTemplate.self,
                from: annotationData
            )
            guard annotation.schemaVersion == 2 else {
                throw BundleError.invalid("sample bundles require schema-v2 annotation provenance")
            }
            guard annotation.source.documentFormat == sourceURL.pathExtension.lowercased() else {
                throw BundleError.invalid("source format does not match annotation provenance")
            }
            let sourceData = try Data(contentsOf: sourceURL)
            guard sha256(sourceData) == annotation.source.sourceSHA256 else {
                throw BundleError.invalid("source SHA-256 does not match annotation provenance")
            }
            let texts = try RepresentativeBookSourceSupport.texts(
                sourceURL: sourceURL,
                sourceUnitKind: annotation.source.sourceUnitKind,
                sourceUnitCount: annotation.source.sourceUnitCount,
                unitNumbers: annotation.source.sampledUnitNumbers
            )
            let joined = texts.joined(separator: "\n\u{001E}\n")
            guard sha256(Data(joined.utf8)) == annotation.sampledTextSHA256 else {
                throw BundleError.invalid("sampled source text changed since annotation generation")
            }

            let bundle = SampleBundle(
                schemaVersion: 1,
                documentAlias: annotation.source.alias,
                sourceSHA256: annotation.source.sourceSHA256,
                annotationSHA256: sha256(annotationData),
                candidateSelectionPolicyVersion: annotation.candidateSelectionPolicyVersion,
                sampledTextSHA256: annotation.sampledTextSHA256,
                languageCode: annotation.source.languageCode,
                documentFormat: annotation.source.documentFormat,
                dataRole: annotation.source.dataRole,
                sourceUnitKind: annotation.source.sourceUnitKind,
                sourceUnitCount: annotation.source.sourceUnitCount,
                sampledUnitNumbers: annotation.source.sampledUnitNumbers,
                sampledTexts: texts,
                containsExtractedProse: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(bundle)
            data.append(0x0A)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
            print("wrote frozen sample bundle to \(outputURL.path)")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(2)
        }
    }
}
