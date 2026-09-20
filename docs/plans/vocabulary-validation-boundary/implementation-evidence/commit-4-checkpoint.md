# POS and cross-format ownership checkpoint (Commit 4)

Reusable POS evaluation and consequence accounting now live in `LeafReaderValidation/Vocabulary`; the existing `evaluate_vocabulary_pos_fixtures.sh` path builds/links Validation plus Core in Swift 6 with warnings as errors, and its Swift command adapter is 15 lines. The selected development fixture still produces byte-identical JSON. No consumed held-out POS case was rescored or used for tuning.

`VocabularyPreparationFixtureXCTests` remains in `LeafReaderAppTests` because it exercises actual PDFKit and EPUB/DOCX document loading plus the final vocabulary pipeline. No Validation-to-App dependency was introduced. A shared comparison helper was not extracted from this single App integration consumer merely for directory symmetry.

Verification:

- `swift build --target LeafReaderValidation -Xswiftc -warnings-as-errors`: passed.
- The standalone POS evaluator report matched the frozen baseline byte-for-byte at SHA-256 `37352bfd604f16d0605af0df673962e8d7166c709c755b7121935128cccd27f9`; its report validator and self-test passed.
- `swift test --filter VocabularyPreparationFixtureXCTests -Xswiftc -warnings-as-errors`: 3 passed across PDF, EPUB, and DOCX fixtures.
- Frozen [four-run Commit 4 parity report](parity-4.json), SHA-256 `08121ebcb973f93b5c4c3c09d6bbb9dfe71303046760f6c63452e0a11f0a951f`: all 13 semantic artifact comparisons and report validators passed.
- Final validation-boundary check and historical v1 reservation self-test passed.

No production lexical identity, occurrence denominator, parser, selector, or objective rule changed. Performance impact remains unmeasured and no improvement is claimed.
