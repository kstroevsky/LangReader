import XCTest
@testable import LeafReaderApp

final class PDFDocumentTextSnapshotCacheXCTests: XCTestCase {
    func testSnapshotCacheRoundTripsAndRejectsMismatchedIdentityOrPageCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-pdf-text-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = PDFDocumentTextSnapshotCache(directoryURL: directory)
        let snapshot = PDFDocumentTextSnapshot(
            documentID: "document-a",
            pageTexts: ["erste Seite", "zweite Seite"]
        )
        cache.save(snapshot, contentFingerprint: "content-a")

        XCTAssertEqual(
            cache.load(documentID: "document-a", contentFingerprint: "content-a", expectedPageCount: 2)?.pageTexts,
            snapshot.pageTexts
        )
        XCTAssertNil(cache.load(documentID: "document-a", contentFingerprint: "content-b", expectedPageCount: 2))
        XCTAssertNil(cache.load(documentID: "document-a", contentFingerprint: "content-a", expectedPageCount: 3))
        XCTAssertNil(cache.load(documentID: "document-b", contentFingerprint: "content-a", expectedPageCount: 2))

        cache.remove(documentID: "document-a")
        XCTAssertNil(cache.load(documentID: "document-a", contentFingerprint: "content-a", expectedPageCount: 2))
    }

    func testSnapshotCacheBoundsRetainedBytesAndKeepsNewestEntry() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("leafreader-pdf-text-cache-limit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = PDFDocumentTextSnapshotCache(directoryURL: directory, maximumBytes: 1)
        cache.save(PDFDocumentTextSnapshot(documentID: "older", pageTexts: ["old text"]), contentFingerprint: "old")
        cache.save(PDFDocumentTextSnapshot(documentID: "newer", pageTexts: ["new text"]), contentFingerprint: "new")

        XCTAssertNil(cache.load(documentID: "older", contentFingerprint: "old", expectedPageCount: 1))
        XCTAssertEqual(
            cache.load(documentID: "newer", contentFingerprint: "new", expectedPageCount: 1)?.pageTexts,
            ["new text"]
        )
    }
}
