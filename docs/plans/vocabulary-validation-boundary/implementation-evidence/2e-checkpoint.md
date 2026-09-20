# Core experiment-code retirement checkpoint (2E)

The old `VocabularyAssessmentCausalDiagnostics.swift` bank implementation and `diagnosticSnapshot(selectionOverride:)` were removed from Core. Core retains only `VocabularyAssessmentObservation`, its construction errors, and the actual production assessment implementation. A/B1/B2, fixed-bank controls, counterfactual selected sets, and bank-specific errors now reside in Validation. The migration-only `parityBankSamples` hooks and same-tree test were removed after the 2C/2D evidence was recorded. Core observation/continuation/replay tests and Validation bank tests remain with their owners.

Verification:

- `swift test --filter VocabularyAssessmentObservationXCTests -Xswiftc -warnings-as-errors`: 4 passed.
- `swift test --filter VocabularyValidationBankXCTests -Xswiftc -warnings-as-errors`: 8 passed.
- `python3 scripts/check_validation_boundary.py --self-test --final`: passed, including negative graph/import fixtures and no migrated validation-only declarations in production.
- `swift build -Xswiftc -warnings-as-errors`: passed.
- `swift test -Xswiftc -warnings-as-errors`: 174 tests, one skip, zero failures.
- Frozen [four-run 2E parity report](parity-2e.json), SHA-256 `42a0bc50344f768ef3cddeaba3b9bfef525034b1f405a7035324ccba43ed09de`: all standard, causal, longitudinal, and POS semantic comparisons and validators passed.
- The historical v1 reservation remains byte-identical at SHA-256 `a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a` and its Git-blob validator self-test passed.

No performance improvement is claimed. Validation is outside the shipping App product dependency closure; its opt-in bank work is not on a product hot path.
