#!/usr/bin/env swift

import Foundation

private enum FixtureFormat: String, Codable, CaseIterable {
    case pdf
    case epub
    case docx
}

private struct Fixture: Codable {
    let format: FixtureFormat
    let alias: String
    let path: String
}

private struct DatasetMetadata: Codable {
    let aiConversationMessages: Int
    let notes: Int
    let vocabularyRecords: Int

    enum CodingKeys: String, CodingKey {
        case aiConversationMessages = "ai_conversation_messages"
        case notes
        case vocabularyRecords = "vocabulary_records"
    }
}

private struct Manifest: Codable {
    let schemaVersion: Int
    let fixtures: [Fixture]
    let datasets: DatasetMetadata

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtures
        case datasets
    }
}

private struct SafeFixtureMetadata: Codable {
    let format: FixtureFormat
    let alias: String
    let sizeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case format
        case alias
        case sizeBytes = "size_bytes"
    }
}

private struct SafeMetadata: Codable {
    let schemaVersion: Int
    let capturedAtUTC: String
    let fixtures: [SafeFixtureMetadata]
    let datasets: DatasetMetadata

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case capturedAtUTC = "captured_at_utc"
        case fixtures
        case datasets
    }
}

private enum ManifestError: Error, CustomStringConvertible {
    case usage
    case invalid(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: private_perf_fixture_manifest.swift validate|paths <manifest> | metadata <manifest> <output>"
        case .invalid(let message):
            return "Invalid private performance manifest: \(message)"
        }
    }
}

private func loadManifest(at path: String) throws -> Manifest {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)
    try validate(manifest)
    return manifest
}

private func validate(_ manifest: Manifest) throws {
    guard manifest.schemaVersion == 1 else {
        throw ManifestError.invalid("schema_version must be 1")
    }

    let actualFormats = Set(manifest.fixtures.map(\.format))
    let requiredFormats = Set(FixtureFormat.allCases)
    guard actualFormats == requiredFormats else {
        let missing = requiredFormats.subtracting(actualFormats).map(\.rawValue).sorted()
        let unexpected = actualFormats.subtracting(requiredFormats).map(\.rawValue).sorted()
        let details = [
            missing.isEmpty ? nil : "missing \(missing.joined(separator: ", "))",
            unexpected.isEmpty ? nil : "unexpected \(unexpected.joined(separator: ", "))"
        ].compactMap { $0 }.joined(separator: "; ")
        throw ManifestError.invalid("fixtures must cover PDF, EPUB, and DOCX (\(details))")
    }

    var aliases = Set<String>()
    for fixture in manifest.fixtures {
        guard aliases.insert(fixture.alias).inserted else {
            throw ManifestError.invalid("fixture aliases must be unique")
        }
        let allowedAlias = fixture.alias.allSatisfy {
            $0.isLowercase || $0.isNumber || $0 == "-"
        }
        guard !fixture.alias.isEmpty, allowedAlias else {
            throw ManifestError.invalid("alias '\(fixture.alias)' must use only lowercase letters, numbers, and hyphens")
        }
        guard fixture.path.hasPrefix("/"), !fixture.path.contains("\n") else {
            throw ManifestError.invalid("every fixture path must be an absolute, single-line path")
        }
        guard URL(fileURLWithPath: fixture.path).pathExtension.lowercased() == fixture.format.rawValue else {
            throw ManifestError.invalid("fixture '\(fixture.alias)' extension does not match \(fixture.format.rawValue)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fixture.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ManifestError.invalid("fixture '\(fixture.alias)' is not a readable file")
        }
    }

    guard manifest.datasets.aiConversationMessages >= 100 else {
        throw ManifestError.invalid("ai_conversation_messages must be at least 100")
    }
    guard manifest.datasets.notes >= 100 else {
        throw ManifestError.invalid("notes must be at least 100")
    }
    guard manifest.datasets.vocabularyRecords >= 1_000 else {
        throw ManifestError.invalid("vocabulary_records must be at least 1000")
    }
}

private func fileSize(at path: String) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let size = attributes[.size] as? NSNumber else {
        throw ManifestError.invalid("could not read fixture size")
    }
    return size.int64Value
}

private func writeMetadata(for manifest: Manifest, to path: String) throws {
    let fixtures = try manifest.fixtures.map { fixture in
        SafeFixtureMetadata(
            format: fixture.format,
            alias: fixture.alias,
            sizeBytes: try fileSize(at: fixture.path)
        )
    }
    let metadata = SafeMetadata(
        schemaVersion: manifest.schemaVersion,
        capturedAtUTC: ISO8601DateFormatter().string(from: Date()),
        fixtures: fixtures,
        datasets: manifest.datasets
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(metadata)
    var output = data
    output.append(0x0A)
    try output.write(to: URL(fileURLWithPath: path), options: .atomic)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2 else { throw ManifestError.usage }
    let manifest = try loadManifest(at: arguments[1])

    switch arguments[0] {
    case "validate" where arguments.count == 2:
        break
    case "paths" where arguments.count == 2:
        for fixture in manifest.fixtures {
            print(fixture.path)
        }
    case "metadata" where arguments.count == 3:
        try writeMetadata(for: manifest, to: arguments[2])
    default:
        throw ManifestError.usage
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
