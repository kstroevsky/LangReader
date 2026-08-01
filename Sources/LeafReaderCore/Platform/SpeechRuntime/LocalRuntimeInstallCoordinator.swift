import Foundation

/// `activeInstalls` is confined to the private serial queue.
package final class LocalRuntimeInstallCoordinator<Key: Hashable>: @unchecked Sendable {
    private let queue: DispatchQueue
    private var activeInstalls = Set<Key>()

    package init(label: String) {
        queue = DispatchQueue(label: label)
    }

    package func ensureNotInstalling(_ key: Key, makeError: () -> NSError) throws {
        let isInstalling = queue.sync {
            activeInstalls.contains(key)
        }
        guard !isInstalling else {
            throw makeError()
        }
    }

    package func perform(_ key: Key, makeError: () -> NSError, work: () throws -> Void) throws {
        let didStart = queue.sync {
            guard !activeInstalls.contains(key) else { return false }
            activeInstalls.insert(key)
            return true
        }
        guard didStart else {
            throw makeError()
        }
        defer {
            queue.sync {
                _ = activeInstalls.remove(key)
            }
        }
        try work()
    }
}
