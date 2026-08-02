import Foundation

/// Monotonic counter bumped whenever cached German form labels are invalidated
/// at runtime — specifically when a flexion table is fetched, which can refine a
/// lemma's labels (finiteVerb -> Präteritum, plural -> a cased plural).
///
/// The library build cache folds this into its fingerprint, so a document is
/// rebuilt after such a change even though none of its stored records moved.
/// Kept dependency-free (Foundation only) so both the flexion store and the
/// build cache can reference it without dragging in the NaturalLanguage-backed
/// labeler.
package enum GermanLabelCacheGeneration {
    private static let lock = NSLock()
    // Guarded by `lock` on every access below; `nonisolated(unsafe)` asserts that
    // to Swift 6, which cannot see that a lock covers a static.
    private nonisolated(unsafe) static var value = 0

    package static var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    package static func bump() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
