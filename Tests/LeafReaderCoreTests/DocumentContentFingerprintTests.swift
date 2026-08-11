import Foundation
import XCTest
@testable import LeafReaderCore

final class DocumentContentFingerprintTests: XCTestCase {
    func testFingerprintIsContentDerivedRatherThanMetadataDerived() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-content-fingerprint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.pdf")
        let second = directory.appendingPathComponent("second.pdf")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try Data("same-size-A".utf8).write(to: first)
        try Data("same-size-B".utf8).write(to: second)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: second.path)

        let firstFingerprint = try XCTUnwrap(DocumentContentFingerprint.sha256(for: first, chunkBytes: 3))
        let secondFingerprint = try XCTUnwrap(DocumentContentFingerprint.sha256(for: second, chunkBytes: 3))
        XCTAssertNotEqual(firstFingerprint, secondFingerprint)

        try Data("same-size-A".utf8).write(to: second)
        XCTAssertEqual(
            firstFingerprint,
            DocumentContentFingerprint.sha256(for: second, chunkBytes: 2)
        )
    }

    func testFingerprintRejectsMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).pdf")
        XCTAssertNil(DocumentContentFingerprint.sha256(for: missing))
    }
}
