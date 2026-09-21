# Parallel bank-evaluator checkpoint (2B)

The new Core observation carrier exposes only `canonicalKey`, `occurrenceCount`, `isIncluded`, `evidence`, `responseCurve`, and `productionKnownMask` per item. It records the actual production selection and immutable posterior/sampling facts. The new Validation evaluator runs A/B1/B2 and fixed-selected-set evaluation using Core's production knowledge/observation model; the old Core evaluator and old standalone wrapper remain intact for same-tree comparison.

Focused evidence:

- `swift test --filter AdaptiveVocabularyAssessmentXCTests -Xswiftc -warnings-as-errors`: 41 passed.
- `swift test --filter VocabularyAssessmentBankParityXCTests -Xswiftc -warnings-as-errors`: 3 passed, including old/new result encodings, minimal observation fields, invalid selection/posterior rejection, and no production-path mutation.
- `python3 scripts/check_validation_boundary.py`: passed.
- `python3 scripts/validate_vocabulary_development_confirmation_reservation.py --self-test`: passed; v1 remains `reservedNotExecuted`.
- Frozen [four-run parity report](parity-2b.json), SHA-256 `72f97317cf4ca5417e6c394da1075514e1df58822c2a0f055b90fc372f0d913c`: standard 2/2, causal 5/5, longitudinal 5/5, POS 1/1 artifact comparisons passed. All four report validators exited 0. Raw timing JSON was retained but not treated as semantic parity.

This is development-fixture evidence for a behavior-preserving extraction, not model-quality improvement or release validation. The old evaluator is still the production-path runner at this checkpoint. 2C must strengthen same-tree bank/mask parity before the wrapper switch.
