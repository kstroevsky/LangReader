import Foundation
import LeafReaderCore

@MainActor
protocol StreamingAnswerProvider {
    func answerStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never>?
}

@MainActor
final class LLMAnswerProvider: StreamingAnswerProvider {
    private let client: AIClient

    init(client: AIClient) {
        self.client = client
    }

    func answerStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never>? {
        let client = client
        return Task { @MainActor in
            var fullText = ""
            do {
                for try await delta in client.stream(messages: messages) {
                    guard !Task.isCancelled else { return }
                    fullText += delta
                    onDelta(delta)
                }
                completion(.success(AIResponseTextFormatter.visibleAnswer(fullText)))
            } catch {
                guard !Task.isCancelled else { return }
                completion(.failure(error))
            }
        }
    }
}
