import CryptoKit
import Foundation

struct RepresentativeBookSampleBundle: Decodable {
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

struct RepresentativeBookCheckpointDescriptor: Encodable {
    let id: String
    let revision: String
}

struct RepresentativeBookExportEnvironment: Encodable {
    let osVersion: String
    let osBuildVersion: String
    let machineArchitecture: String
    let xcodeVersion: String
    let swiftVersion: String
    let naturalLanguageRuntime: String
    let languageSelectionMode: String
    let dictionaryAttestationState: String
    let experimentHarnessSHA256: String
}

struct RepresentativeBookExportAnalysis: Encodable {
    let lemma: String
    let partOfSpeech: String
    let source: String
    let rawScore: Double?
    let confidence: String
}

struct RepresentativeBookCheckpointRecord: Encodable {
    let assignmentID: String
    let physicalOccurrenceID: String
    let sampledUnitIndex: Int
    let sourceUnitNumber: Int
    let utf16Location: Int
    let utf16Length: Int
    let surface: String
    let requestedLanguage: String
    let detectedLanguage: String?
    let routedLanguage: String?
    let lemmaOrAnchor: String?
    let anchorKey: String?
    let predictedPartOfSpeech: String?
    let finalLexicalKey: String?
    let resolutionState: String?
    let assessmentIdentityPolicy: String?
    let contextFingerprint: String
    let providers: [String]
    let reconcilerVersion: String?
    let analyses: [RepresentativeBookExportAnalysis]
}

struct RepresentativeBookCheckpointExport: Encodable {
    let schemaVersion: Int
    let checkpoint: RepresentativeBookCheckpointDescriptor
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
    let environment: RepresentativeBookExportEnvironment
    let records: [RepresentativeBookCheckpointRecord]
}

enum RepresentativeBookCheckpointExportError: Error, CustomStringConvertible {
    case usage
    case invalid(String)

    var description: String {
        switch self {
        case .usage:
            "usage: checkpoint-export <sample-bundle.json> <output.json> <checkpoint-id> <revision> <harness-sha256>"
        case .invalid(let message):
            message
        }
    }
}

func representativeBookSHA256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

func representativeBookPhysicalOccurrenceID(
    unitIndex: Int,
    location: Int,
    length: Int
) -> String {
    "u\(unitIndex):\(location):\(length)"
}

func representativeBookContextFingerprint(
    text: String,
    location: Int,
    length: Int
) -> String {
    let nsText = text as NSString
    let safeLocation = max(0, min(location, nsText.length))
    let safeEnd = max(safeLocation, min(location + length, nsText.length))
    let lower = max(0, safeLocation - 90)
    let upper = min(nsText.length, safeEnd + 90)
    let context = nsText.substring(with: NSRange(location: lower, length: upper - lower))
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    return representativeBookSHA256(context)
}

func representativeBookShellOutput(_ executable: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !value.isEmpty ? value : "unavailable"
    } catch {
        return "unavailable"
    }
}

func representativeBookMachineArchitecture() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}

func representativeBookEnvironment(
    naturalLanguageRuntime: String,
    languageSelectionMode: String,
    experimentHarnessSHA256: String
) -> RepresentativeBookExportEnvironment {
    RepresentativeBookExportEnvironment(
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        osBuildVersion: representativeBookShellOutput("/usr/bin/sw_vers", ["-buildVersion"]),
        machineArchitecture: representativeBookMachineArchitecture(),
        xcodeVersion: representativeBookShellOutput("/usr/bin/xcrun", ["xcodebuild", "-version"]),
        swiftVersion: representativeBookShellOutput("/usr/bin/xcrun", ["swiftc", "--version"]),
        naturalLanguageRuntime: naturalLanguageRuntime,
        languageSelectionMode: languageSelectionMode,
        dictionaryAttestationState: "notEvaluatedByCheckpointExporter",
        experimentHarnessSHA256: experimentHarnessSHA256
    )
}

func representativeBookReadBundle(_ path: String) throws -> RepresentativeBookSampleBundle {
    let bundle = try JSONDecoder().decode(
        RepresentativeBookSampleBundle.self,
        from: Data(contentsOf: URL(fileURLWithPath: path))
    )
    guard bundle.schemaVersion == 1,
          bundle.containsExtractedProse,
          bundle.sampledTexts.count == bundle.sampledUnitNumbers.count,
          !bundle.sampledTexts.isEmpty else {
        throw RepresentativeBookCheckpointExportError.invalid("invalid representative-book sample bundle")
    }
    let joined = bundle.sampledTexts.joined(separator: "\n\u{001E}\n")
    guard representativeBookSHA256(joined) == bundle.sampledTextSHA256 else {
        throw RepresentativeBookCheckpointExportError.invalid("sample bundle text hash does not match provenance")
    }
    return bundle
}

func representativeBookWriteExport(
    _ value: RepresentativeBookCheckpointExport,
    path: String
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}
