import Foundation

/// All mutable dictionaries are confined to the private serial queue.
package final class LocalRuntimeDownloadCoordinator<Key: Hashable>: @unchecked Sendable {
    package typealias Completion = (Result<Void, Error>) -> Void

    private let queue: DispatchQueue
    private var completions: [Key: [Completion]] = [:]
    private var downloadIDs: [Key: UUID] = [:]
    private var tasks: [Key: URLSessionTask] = [:]
    private var downloaders: [Key: LocalRuntimeDownloader] = [:]
    private var progressValues: [Key: Double] = [:]
    private var pausedKeys = Set<Key>()

    package init(label: String) {
        queue = DispatchQueue(label: label)
    }

    package func isDownloading(_ key: Key) -> Bool {
        queue.sync { completions[key] != nil }
    }

    package func isPaused(_ key: Key) -> Bool {
        queue.sync { pausedKeys.contains(key) }
    }

    package func pause(_ key: Key) {
        queue.sync {
            guard completions[key] != nil else { return }
            tasks[key]?.suspend()
            pausedKeys.insert(key)
        }
    }

    package func resume(_ key: Key) {
        queue.sync {
            guard completions[key] != nil else { return }
            tasks[key]?.resume()
            pausedKeys.remove(key)
        }
    }

    package func progress(for key: Key) -> Double? {
        queue.sync {
            guard completions[key] != nil,
                  let progress = tasks[key]?.progress.fractionCompleted,
                  progress.isFinite,
                  progress >= 0 else {
                return progressValues[key]
            }
            return progressValues[key] ?? progress
        }
    }

    package func begin(_ key: Key, completion: @escaping Completion) -> UUID? {
        queue.sync {
            if completions[key] != nil {
                completions[key]?.append(completion)
                return nil
            }
            let downloadID = UUID()
            completions[key] = [completion]
            downloadIDs[key] = downloadID
            return downloadID
        }
    }

    package func stop(_ key: Key) -> [Completion] {
        queue.sync {
            let completions = completions[key] ?? []
            let task = tasks[key]
            clearState(for: key)
            task?.cancel()
            return completions
        }
    }

    package func finish(_ key: Key, downloadID: UUID) -> [Completion] {
        queue.sync {
            guard downloadIDs[key] == downloadID else {
                return []
            }
            let completions = completions[key] ?? []
            clearState(for: key)
            return completions
        }
    }

    package func isCurrent(_ key: Key, downloadID: UUID) -> Bool {
        queue.sync { downloadIDs[key] == downloadID }
    }

    package func attach(
        key: Key,
        downloadID: UUID,
        task: URLSessionTask,
        downloader: LocalRuntimeDownloader,
        resumedFromPartial: Bool
    ) -> Bool {
        queue.sync {
            guard downloadIDs[key] == downloadID else {
                return false
            }
            tasks[key] = task
            downloaders[key] = downloader
            progressValues[key] = resumedFromPartial ? nil : 0
            return true
        }
    }

    package func updateProgress(key: Key, downloadID: UUID, completedBytes: Int64, expectedBytes: Int64?) {
        guard let expectedBytes, expectedBytes > 0 else { return }
        queue.sync {
            guard downloadIDs[key] == downloadID else { return }
            progressValues[key] = min(1, max(0, Double(completedBytes) / Double(expectedBytes)))
        }
    }

    private func clearState(for key: Key) {
        completions[key] = nil
        downloadIDs[key] = nil
        tasks[key] = nil
        downloaders[key] = nil
        progressValues[key] = nil
        pausedKeys.remove(key)
    }
}
