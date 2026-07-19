# AI Analysis Cache

关键词：整本书问答、AI 分析、embedding、缓存、检索、PDF 问答、文档问答。

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
- Button labels should match scope: `生成/更新本书缓存` fills missing current-book embeddings, `清除本书分析缓存` deletes only the current book's embeddings, and `清除全部缓存` deletes all local embedding cache rows.

## Related Files

- `Sources/LeafReaderApp/AIConversation/ReaderWindowController+Embedding.swift`
- `Sources/LeafReaderApp/AIConversation/ReaderWindowController+EmbeddingBackfill.swift`
- `Sources/LeafReaderApp/AIConversation/ReaderWindowController+EmbeddingStatus.swift`
- `Sources/LeafReaderApp/AIConversation/PDFDocumentAgentIndex.swift`
- `Sources/LeafReaderApp/AIConversation/PDFEmbeddingStore.swift`
- `Sources/LeafReaderApp/Platform/Networking/EmbeddingClient.swift`
- `Sources/LeafReaderApp/AIConversation/EmbeddingActionPolicy.swift`
