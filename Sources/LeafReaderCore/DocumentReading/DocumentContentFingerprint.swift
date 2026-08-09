import CryptoKit
import Foundation

/// A content-derived identity for persisted derived data. The reader's user
/// session ID deliberately remains path-based for fast launch and migration,
/// while caches that can safely be rebuilt use this full streaming digest to
/// reject same-path/same-size/same-mtime replacements.
package enum DocumentContentFingerprint {
    package static func sha256(for url: URL, chunkBytes: Int = 1_048_576) -> String? {
        guard chunkBytes > 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: chunkBytes), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
