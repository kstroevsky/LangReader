import Foundation
import XCTest
@testable import LeafReaderCore

final class DOCXPreparedCacheTests: XCTestCase {
    private final class ConcurrentResults: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Result<WebReadableDocument, Error>] = []

        func append(_ result: Result<WebReadableDocument, Error>) {
            lock.lock()
            storage.append(result)
            lock.unlock()
        }

        func snapshot() -> [Result<WebReadableDocument, Error>] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private final class CancellationResult: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Error?

        func store(_ error: Error?) {
            lock.lock()
            storage = error
            lock.unlock()
        }

        func error() -> Error? {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    func testMissBuildsPreparedEntryAndHitLoadsItWithoutRenderingAgain() throws {
        let fixture = try makeFixture(title: "Cache", paragraphs: ["Heading", "Body"], withImage: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)

        let miss = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        let hit = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)

        XCTAssertTrue(miss.html.isEmpty)
        XCTAssertNotNil(miss.htmlFileURL)
        XCTAssertEqual(miss.plainText, "Heading\n\nBody")
        XCTAssertEqual(miss.tocItems.map(\.title), ["Heading"])
        XCTAssertTrue(miss.loadMeasurements.contains { $0.event == .docxXMLRender })
        XCTAssertFalse(miss.loadMeasurements.contains { $0.event == .docxCacheHitLoad })
        XCTAssertEqual(hit.plainText, miss.plainText)
        XCTAssertEqual(hit.htmlFileURL, miss.htmlFileURL)
        XCTAssertTrue(hit.loadMeasurements.contains { $0.event == .docxCacheHitLoad })
        XCTAssertFalse(hit.loadMeasurements.contains { $0.event == .docxXMLRender })
        let html = try String(contentsOf: try XCTUnwrap(hit.htmlFileURL), encoding: .utf8)
        XCTAssertTrue(html.contains("word/media/image%201.png"))
        XCTAssertFalse(html.contains("file://"))
    }

    func testCacheKeyUsesTitleAndFullContentFingerprint() throws {
        let fixture = try makeFixture(title: "First", paragraphs: ["Version one"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)
        let renamed = fixture.root.appendingPathComponent("Renamed.docx")
        try FileManager.default.copyItem(at: fixture.docx, to: renamed)

        _ = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        _ = try WebDocumentLoader.loadPreparedDOCX(url: renamed, cacheRootURL: cache)
        XCTAssertEqual(try cacheEntries(in: cache).count, 2)

        let originalModificationDate = try fixture.docx.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let replacement = try makeFixture(title: "Replacement", paragraphs: ["Version two"])
        defer { try? FileManager.default.removeItem(at: replacement.root) }
        try FileManager.default.removeItem(at: fixture.docx)
        try FileManager.default.copyItem(at: replacement.docx, to: fixture.docx)
        if let originalModificationDate {
            try FileManager.default.setAttributes([.modificationDate: originalModificationDate], ofItemAtPath: fixture.docx.path)
        }
        let changed = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        XCTAssertEqual(changed.plainText, "Version two")
        XCTAssertEqual(try cacheEntries(in: cache).count, 3)
    }

    func testCorruptEntryIsRemovedAndRebuiltOnce() throws {
        let fixture = try makeFixture(title: "Corrupt", paragraphs: ["Still readable"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)
        let first = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        let entry = try XCTUnwrap(first.htmlFileURL?.deletingLastPathComponent())
        try Data("tampered".utf8).write(to: entry.appendingPathComponent("plain-text.txt"))

        let rebuilt = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        XCTAssertEqual(rebuilt.plainText, "Still readable")
        XCTAssertTrue(rebuilt.loadMeasurements.contains { $0.event == .docxXMLRender })
        XCTAssertFalse(rebuilt.loadMeasurements.contains { $0.event == .docxCacheHitLoad })
    }

    func testSchemaMismatchIsInvalidatedAndRebuilt() throws {
        let fixture = try makeFixture(title: "Schema", paragraphs: ["Current schema"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)
        let first = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        let manifestURL = try XCTUnwrap(first.htmlFileURL?.deletingLastPathComponent())
            .appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        manifest["schemaVersion"] = -1
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: manifestURL)

        let rebuilt = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache)
        XCTAssertEqual(rebuilt.plainText, "Current schema")
        XCTAssertTrue(rebuilt.loadMeasurements.contains { $0.event == .docxXMLRender })
    }

    func testUnavailableCacheRootFallsBackWithoutFailingTheDocument() throws {
        let fixture = try makeFixture(title: "Fallback", paragraphs: ["Readable fallback"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unavailable = fixture.root.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: unavailable)

        let document = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: unavailable)
        XCTAssertEqual(document.plainText, "Readable fallback")
        XCTAssertNil(document.htmlFileURL)
        XCTAssertFalse(document.html.isEmpty)
    }

    func testUnsafeArchivePathsAreRejectedBeforeExtraction() throws {
        XCTAssertThrowsError(try WebDocumentLoader.validatedDOCXArchiveEntries([
            "word/document.xml", "../escape.txt"
        ]))
        XCTAssertThrowsError(try WebDocumentLoader.validatedDOCXArchiveEntries([
            "word/document.xml", "word/media/../../escape.png"
        ]))
        XCTAssertEqual(
            try WebDocumentLoader.validatedDOCXArchiveEntries([
                "word/document.xml", "word/_rels/document.xml.rels", "word/media/image.png", "docProps/core.xml"
            ]),
            ["word/document.xml", "word/_rels/document.xml.rels", "word/media/image.png"]
        )
    }

    func testEvictionHonorsEntryAndByteLimits() throws {
        let fixture = try makeFixture(title: "One", paragraphs: ["One"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let second = fixture.root.appendingPathComponent("Two.docx")
        try FileManager.default.copyItem(at: fixture.docx, to: second)
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)
        let oneEntry = DOCXPreparedCachePolicy(maximumBytes: 512 * 1_024 * 1_024, maximumEntries: 1)

        _ = try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache, policy: oneEntry)
        _ = try WebDocumentLoader.loadPreparedDOCX(url: second, cacheRootURL: cache, policy: oneEntry)
        XCTAssertEqual(try cacheEntries(in: cache).count, 1)

        let oversizedCache = fixture.root.appendingPathComponent("oversized", isDirectory: true)
        let transient = try WebDocumentLoader.loadPreparedDOCX(
            url: fixture.docx,
            cacheRootURL: oversizedCache,
            policy: DOCXPreparedCachePolicy(maximumBytes: 1, maximumEntries: 10)
        )
        XCTAssertNotNil(transient.htmlFileURL)
        XCTAssertTrue(try cacheEntries(in: oversizedCache).isEmpty)
    }

    func testConcurrentBuildersConvergeOnOneCompleteEntry() throws {
        let fixture = try makeFixture(title: "Race", paragraphs: Array(repeating: "Concurrent", count: 100))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)
        let results = ConcurrentResults()
        let group = DispatchGroup()
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                let result = Result { try WebDocumentLoader.loadPreparedDOCX(url: fixture.docx, cacheRootURL: cache) }
                results.append(result)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
        let captured = results.snapshot()
        XCTAssertEqual(captured.count, 2)
        let documents = try captured.map { try $0.get() }
        XCTAssertEqual(documents[0].plainText, documents[1].plainText)
        XCTAssertEqual(try cacheEntries(in: cache).count, 1)
    }

    func testCancellationAbortsPreparationAndRemovesTemporaryEntry() throws {
        let fixture = try makeFixture(
            title: "Cancel",
            paragraphs: Array(repeating: "A deliberately repeated paragraph", count: 100_000)
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("cache", isDirectory: true)
        let token = DocumentLoadCancellationToken()
        let result = CancellationResult()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try WebDocumentLoader.loadPreparedDOCX(
                    url: fixture.docx,
                    cacheRootURL: cache,
                    cancellationToken: token
                )
                result.store(nil)
            } catch {
                result.store(error)
            }
            finished.signal()
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
            if names.contains(where: { $0.hasPrefix(".building-") }) { break }
            Thread.sleep(forTimeInterval: 0.002)
        }
        token.cancel()
        XCTAssertEqual(finished.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(result.error() is CancellationError)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".building-") })
        XCTAssertTrue(try cacheEntries(in: cache).isEmpty)
    }

    private struct Fixture {
        let root: URL
        let docx: URL
    }

    private func makeFixture(title: String, paragraphs: [String], withImage: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-DOCXCacheTests-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("package", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        let relationships = word.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: relationships, withIntermediateDirectories: true)
        if withImage {
            let media = word.appendingPathComponent("media", isDirectory: true)
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
            try Data([0x89, 0x50, 0x4e, 0x47]).write(to: media.appendingPathComponent("image 1.png"))
        }
        let body = paragraphs.enumerated().map { index, text in
            let style = index == 0 && paragraphs.count > 1 ? "<w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr>" : ""
            return "<w:p>\(style)<w:r><w:t>\(escapedXML(text))</w:t></w:r></w:p>"
        }.joined() + (withImage ? "<w:p><w:r><w:drawing><a:blip r:embed=\"image\"/></w:drawing></w:r></w:p>" : "")
        let document = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body>\(body)</w:body></w:document>
        """
        try Data(document.utf8).write(to: word.appendingPathComponent("document.xml"))
        let rels = withImage
            ? "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"image\" Target=\"media/image 1.png\"/></Relationships>"
            : "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>"
        try Data(rels.utf8).write(to: relationships.appendingPathComponent("document.xml.rels"))
        let docx = root.appendingPathComponent("\(title).docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", docx.path, "."]
        process.currentDirectoryURL = package
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return Fixture(root: root, docx: docx)
    }

    private func cacheEntries(in root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    private func escapedXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
