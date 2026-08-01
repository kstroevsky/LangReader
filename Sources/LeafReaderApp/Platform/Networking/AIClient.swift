import Foundation
import LeafReaderCore

final class AIClient: Sendable {

    @discardableResult
    func send(messages: [ChatMessage], completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        let callback = AIClientCallback(completion)
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !config.requiresAPIKey || !apiKey.isEmpty else {
            callback.call(.failure(Self.missingAPIKeyError(for: config)))
            return nil
        }

        let request: URLRequest
        do {
            request = try AIChatRequestBuilder.request(
                for: config,
                apiKey: apiKey,
                messages: messages,
                stream: false
            )
        } catch {
            callback.call(.failure(error))
            return nil
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                callback.call(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                callback.call(.failure(NSError(domain: config.provider, code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: NetworkErrorFormatter.httpErrorDescription(
                        prefix: config.displayName,
                        statusCode: http.statusCode,
                        body: body
                    )
                ])))
                return
            }

            guard let data = data else {
                callback.call(.failure(NSError(domain: config.provider, code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No response data"
                ])))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let content = AIChatResponseDecoder.responseText(from: json, config: config) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(domain: config.provider, code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected response: \(body)"
                    ])
                }
                callback.call(.success(AIResponseTextFormatter.visibleAnswer(content)))
            } catch {
                callback.call(.failure(error))
            }
        }
        task.resume()
        return task
    }

    @discardableResult
    func sendStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> Task<Void, Never>? {
        let deltaCallback = AIClientCallback(onDelta)
        let completionCallback = AIClientCallback(completion)
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !config.requiresAPIKey || !apiKey.isEmpty else {
            completionCallback.call(.failure(Self.missingAPIKeyError(for: config)))
            return nil
        }

        let request: URLRequest
        do {
            request = try AIChatRequestBuilder.request(
                for: config,
                apiKey: apiKey,
                messages: messages,
                stream: true
            )
        } catch {
            completionCallback.call(.failure(error))
            return nil
        }

        let task = Task {
            var fullText = ""
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
                        if body.count > 8192 {
                            break
                        }
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
                    guard let delta = AIChatResponseDecoder.deltaText(fromStreamLine: line, config: config), !delta.isEmpty else { continue }
                    fullText += delta
                    deltaCallback.call(delta)
                }

                completionCallback.call(.success(AIResponseTextFormatter.visibleAnswer(fullText)))
            } catch {
                completionCallback.call(.failure(error))
            }
        }
        return task
    }

    private static func missingAPIKeyError(for config: AIModelConfig) -> NSError {
        NSError(domain: config.provider, code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for \(config.displayName). Open settings and configure the API key."
        ])
    }

}

/// URLSession and unstructured tasks require sendable captures, while callers
/// deliberately receive their callbacks on the queues they already select.
/// The box transfers the closure as an opaque value; it never invokes a callback
/// concurrently on its own.
private final class AIClientCallback<Value>: @unchecked Sendable {
    private let callback: (Value) -> Void

    init(_ callback: @escaping (Value) -> Void) {
        self.callback = callback
    }

    func call(_ value: Value) {
        callback(value)
    }
}
