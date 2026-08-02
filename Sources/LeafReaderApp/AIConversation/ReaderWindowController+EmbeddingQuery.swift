import Foundation

extension ReaderWindowController {
    func queryEmbedding(for question: String, completion: @escaping ([Float]?) -> Void) {
        guard let config = EmbeddingClient.configFromCurrentAISettings() else {
            completion(nil)
            return
        }
        embeddingQueryTask?.cancel()
        embeddingQueryTask = Task { [weak self] in
            guard let self else { return }
            let embeddings = try? await self.embeddingClient.embed(texts: [question], config: config)
            guard !Task.isCancelled else { return }
            self.embeddingQueryTask = nil
            completion(embeddings?.first)
        }
    }
}
