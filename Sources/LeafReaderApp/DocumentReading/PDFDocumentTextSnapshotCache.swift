import CryptoKit
import Foundation
import LeafReaderCore

/// Disk-backed derived text for warm reopens. PDFKit remains authoritative:
/// document identity, page count, parser contract, and OS runtime must all
/// match before cached offsets can seed vocabulary work.
struct PDFDocumentTextSnapshotCache: Sendable {
    private static let parserVersion = 2
    private static let defaultMaximumBytes: Int64 = 256 * 1_024 * 1_024

    private struct Payload: Codable {
        let parserVersion: Int
        let runtimeVersion: String
        let documentID: String
        let contentFingerprint: String
        let pageTexts: [String]
    }

    private let directoryURL: URL?
    private let maximumBytes: Int64

    init(
        directoryURL: URL? = Self.defaultDirectoryURL(),
        maximumBytes: Int64 = Self.defaultMaximumBytes
    ) {
        self.directoryURL = directoryURL
        self.maximumBytes = max(0, maximumBytes)
    }

    func load(
        documentID: String,
        contentFingerprint: String,
        expectedPageCount: Int
    ) -> PDFDocumentTextSnapshot? {
        guard expectedPageCount >= 0,
              let cacheURL = cacheURL(documentID: documentID),
              let data = try? Data(contentsOf: cacheURL, options: .mappedIfSafe),
              let payload = try? PropertyListDecoder().decode(Payload.self, from: data),
              payload.parserVersion == Self.parserVersion,
              payload.runtimeVersion == Self.runtimeVersion,
              payload.documentID == documentID,
              payload.contentFingerprint == contentFingerprint,
              payload.pageTexts.count == expectedPageCount else { return nil }
        return PDFDocumentTextSnapshot(documentID: documentID, pageTexts: payload.pageTexts)
    }

    func save(_ snapshot: PDFDocumentTextSnapshot, contentFingerprint: String) {
        guard let directoryURL,
              let cacheURL = cacheURL(documentID: snapshot.documentID) else { return }
        let payload = Payload(
            parserVersion: Self.parserVersion,
            runtimeVersion: Self.runtimeVersion,
            documentID: snapshot.documentID,
            contentFingerprint: contentFingerprint,
            pageTexts: snapshot.pageTexts
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            pruneIfNeeded(keeping: cacheURL)
        } catch {
            NSLog("LeafReader PDF text cache write failed: %@", error.localizedDescription)
        }
    }

    func remove(documentID: String) {
        guard let cacheURL = cacheURL(documentID: documentID) else { return }
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func cacheURL(documentID: String) -> URL? {
        guard let directoryURL else { return nil }
        let identity = "\(Self.parserVersion)|\(Self.runtimeVersion)|\(documentID)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent("\(digest).plist", isDirectory: false)
    }

    private func pruneIfNeeded(keeping currentURL: URL) {
        guard let directoryURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let currentPath = currentURL.standardizedFileURL.path
        let candidates = entries.compactMap {
            url -> (url: URL, bytes: Int64, modifiedAt: Date, isCurrent: Bool)? in
            guard url.pathExtension == "plist",
                  let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                  ]),
                  values.isRegularFile == true else { return nil }
            return (
                url,
                Int64(values.fileSize ?? 0),
                values.contentModificationDate ?? .distantPast,
                url.standardizedFileURL.path == currentPath
            )
        }.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.modifiedAt > rhs.modifiedAt
        }

        var retainedBytes: Int64 = 0
        for candidate in candidates {
            if candidate.isCurrent || retainedBytes + candidate.bytes <= maximumBytes {
                retainedBytes += candidate.bytes
            } else {
                try? FileManager.default.removeItem(at: candidate.url)
            }
        }
    }

    private static var runtimeVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func defaultDirectoryURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("PDFTextSnapshots", isDirectory: true)
    }
}
