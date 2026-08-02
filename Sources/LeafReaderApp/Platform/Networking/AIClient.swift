import Foundation
import LeafReaderCore

/// Network transport is value-oriented: callers own the Task that awaits a
/// response or consumes the stream.  No opaque callback box crosses URLSession
/// concurrency domains.
final class AIClient: Sendable {
    func response(messages: [ChatMessage]) async throws -> String {
        let (request, config) = try request(messages: messages, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data, config: config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = AIChatResponseDecoder.responseText(from: json, config: config) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: config.provider, code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected response: \(body)"
            ])
        }
        return AIResponseTextFormatter.visibleAnswer(content)
    }

    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        do {
            let (request, config) = try request(messages: messages, stream: true)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else {
                            throw NSError(domain: config.provider, code: -1, userInfo: [
                                NSLocalizedDescriptionKey: "Invalid response"
                            ])
                        }
                        guard (200...299).contains(http.statusCode) else {
                            var body = ""
                            for try await line in bytes.lines {
                                body += line
                                if body.count > 8192 { break }
                            }
                            throw NSError(domain: config.provider, code: http.statusCode, userInfo: [
                                NSLocalizedDescriptionKey: NetworkErrorFormatter.httpErrorDescription(
                                    prefix: config.displayName,
                                    statusCode: http.statusCode,
                                    body: body
                                )
                            ])
                        }
                        for try await line in bytes.lines {
                            guard let delta = AIChatResponseDecoder.deltaText(fromStreamLine: line, config: config),
                                  !delta.isEmpty else { continue }
                            continuation.yield(delta)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private func request(messages: [ChatMessage], stream: Bool) throws -> (URLRequest, AIModelConfig) {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !config.requiresAPIKey || !apiKey.isEmpty else {
            throw Self.missingAPIKeyError(for: config)
        }
        return (try AIChatRequestBuilder.request(for: config, apiKey: apiKey, messages: messages, stream: stream), config)
    }

    private func validate(response: URLResponse, data: Data, config: AIModelConfig) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: config.provider, code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: config.provider, code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: NetworkErrorFormatter.httpErrorDescription(
                    prefix: config.displayName,
                    statusCode: http.statusCode,
                    body: body
                )
            ])
        }
    }

    private static func missingAPIKeyError(for config: AIModelConfig) -> NSError {
        NSError(domain: config.provider, code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for \(config.displayName). Open settings and configure the API key."
        ])
    }
}
