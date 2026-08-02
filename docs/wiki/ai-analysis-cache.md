# AI Analysis Cache

Keywords: whole-book Q&A, AI analysis, embeddings, cache, retrieval, PDF questions, document questions.

AI analysis data is the local embedding/cache layer used for document-aware Q&A.

## Flow

```text
Open document
  -> Build text chunks
  -> EmbeddingClient
  -> PDFEmbeddingStore

Question
  -> Retrieval from cached analysis data
  -> Prompt
  -> AIChatPanel
```

## Files

- `ReaderWindowController+Embedding.swift`: background AI analysis state, progress, cache restore, controls.
- `PDFDocumentAgentIndex.swift`: chunking and retrieval scoring.
- `PDFEmbeddingStore.swift`: local SQLite-backed embedding cache.
- `EmbeddingClient.swift`: embedding API client.
- `AISettingsPanelController*.swift`: model and AI analysis settings UI.

## User-Facing Terms

- UI should prefer “AI analysis data” or “AI analysis cache” over “vector index” unless the setting is explicitly about an embedding model/provider.
- Button labels should match scope: Generate/Update Book Cache fills missing current-book embeddings, Clear Book Analysis Cache deletes only the current book's embeddings, and Clear All Cache deletes all local embedding cache rows.

## Related Files

- `Sources/LeafReaderApp/AIConversation/ReaderWindowController+Embedding.swift`
- `Sources/LeafReaderApp/AIConversation/ReaderWindowController+EmbeddingBackfill.swift`
- `Sources/LeafReaderApp/AIConversation/ReaderWindowController+EmbeddingStatus.swift`
- `Sources/LeafReaderApp/AIConversation/PDFDocumentAgentIndex.swift`
- `Sources/LeafReaderCore/AIConversation/PDFEmbeddingStore.swift`
- `Sources/LeafReaderApp/Platform/Networking/EmbeddingClient.swift`
- `Sources/LeafReaderCore/AIConversation/EmbeddingActionPolicy.swift`
