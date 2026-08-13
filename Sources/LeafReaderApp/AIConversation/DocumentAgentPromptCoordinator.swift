import Foundation

/// Owns the lifecycle of independent document-agent prompt requests.
///
/// The reader window supplies the actual snapshot/retrieval operation, while
/// this coordinator guarantees that cancellation and completion affect only
/// the matching consumer. It deliberately knows nothing about AppKit or how AI
/// responses are rendered.
@MainActor
final class DocumentAgentPromptCoordinator {
    typealias RequestID = UUID
    typealias Finish = (String?) -> Void
    typealias Operation = (RequestID, @escaping Finish) -> Void

    private var activeRequestIDs = Set<RequestID>()
    private var completions: [RequestID: Finish] = [:]
    private var auxiliaryTasks: [RequestID: Task<Void, Never>] = [:]

    var activeRequestCount: Int { activeRequestIDs.count }

    func request(starting operation: @escaping Operation) async -> String? {
        let requestID = begin()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                guard attachCompletion(
                    { continuation.resume(returning: $0) },
                    to: requestID
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                operation(requestID) { [weak self] value in
                    self?.complete(requestID, value: value)
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel(requestID)
            }
        })
    }

    @discardableResult
    func request(
        starting operation: @escaping Operation,
        completion: @escaping Finish
    ) -> RequestID {
        let requestID = begin()
        guard attachCompletion(completion, to: requestID) else {
            completion(nil)
            return requestID
        }
        operation(requestID) { [weak self] value in
            self?.complete(requestID, value: value)
        }
        return requestID
    }

    func isActive(_ requestID: RequestID) -> Bool {
        activeRequestIDs.contains(requestID)
    }

    func replaceAuxiliaryTask(_ task: Task<Void, Never>, for requestID: RequestID) {
        guard isActive(requestID) else {
            task.cancel()
            return
        }
        auxiliaryTasks.removeValue(forKey: requestID)?.cancel()
        auxiliaryTasks[requestID] = task
    }

    func auxiliaryTaskCompleted(for requestID: RequestID) {
        auxiliaryTasks.removeValue(forKey: requestID)
    }

    func cancel(_ requestID: RequestID) {
        complete(requestID, value: nil)
    }

    func cancelAll() {
        for requestID in activeRequestIDs {
            cancel(requestID)
        }
    }

    private func begin() -> RequestID {
        let requestID = RequestID()
        activeRequestIDs.insert(requestID)
        return requestID
    }

    private func attachCompletion(_ completion: @escaping Finish, to requestID: RequestID) -> Bool {
        guard isActive(requestID) else { return false }
        completions[requestID] = completion
        return true
    }

    private func complete(_ requestID: RequestID, value: String?) {
        guard activeRequestIDs.remove(requestID) != nil else { return }
        auxiliaryTasks.removeValue(forKey: requestID)?.cancel()
        completions.removeValue(forKey: requestID)?(value)
    }
}
