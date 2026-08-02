# Vocabulary and Word Highlights

Keywords: vocabulary, review, SRS, highlights, Anki CSV, export.

Leaf Reader stores words, explanations, source context, and highlight locations. Highlights are restored when PDF, EPUB, or DOCX content is reopened.

## Flow

```text
Select a word
  -> Query AI or the local dictionary
  -> Save the vocabulary record in SQLite
  -> Restore its PDF or web highlight when reopened
  -> Review with SRS or export
```

Selections containing more than one word skip local dictionary lookup so phrases are not treated as single dictionary entries.

## Learning Statistics

The vocabulary panel shows the current book's total word count, reviews completed today, mastered words, estimated accuracy, and review streak. Estimated accuracy uses SRS review and lapse counts as a lightweight progress indicator.

## Review and Storage

- `VocabularySRS` manages review intervals and mastery state.
- Frequent, due, and current-book words receive display priority.
- Local dictionary tags are reused by vocabulary details.
- Deleting a word also removes its lookup keys and related metadata.
- PDF records store page indexes and bounds for highlight restoration.
- EPUB and DOCX records store surrounding text, occurrence index, and scroll progress.
- Web text matching normalizes whitespace to remain stable after layout changes.

## Main Files

- `ReaderWindowController+Vocabulary*.swift`: vocabulary UI, actions, review, export, and persistence.
- `ReaderWindowController+VocabularyHighlights.swift`: restored reader highlights.
- `ReaderWindowController+VocabularyReviewUI.swift`: review interface.
- `WordRecordSQLiteStore.swift`: production SQLite storage.
- `StoredPDFWordRect.swift`: PDF highlight geometry.
- `VocabularyLearningStats.swift`: learning statistics.
- `VocabularySRS.swift`: spaced-repetition rules.
- `VocabularyExporter.swift`: Anki CSV and other exports.
- `Resources/reader-web.js`: WebKit selection, matching, and highlight restoration.
