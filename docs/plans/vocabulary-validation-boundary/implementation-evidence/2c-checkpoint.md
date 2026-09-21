# Same-tree diagnostic parity checkpoint (2C)

The old Core bank evaluator and new Validation evaluator were run on identical production assessment states. Tests compared exact production-A, B1, and B2 theta-index arrays and known-mask words at 512 and 1,024 samples with multiple independent seeds. Result encodings, fingerprints, histograms, quantiles, target-miss probabilities, and fixed-selected-set counterfactuals matched. An independent four-world fixed-bank oracle, missing/excluded-key rejection, invalid B1 count rejection, minimal observation fields, and no production-path mutation also passed.

Verification:

- `swift test --filter VocabularyAssessmentBankParityXCTests -Xswiftc -warnings-as-errors`: 4 passed.
- `swift test --filter VocabularyAssessmentCausalDiagnosticsXCTests -Xswiftc -warnings-as-errors`: 11 passed.
- `python3 scripts/check_validation_boundary.py --self-test`: passed.
- `python3 scripts/validate_vocabulary_development_confirmation_reservation.py --self-test`: passed.
- Frozen [four-run 2C parity report](parity-2c.json), SHA-256 `bc5b1d978958b41aa83ddf9ac0d936f8ef104408226f682e694eef4f0771a185`: standard, causal, longitudinal, and POS semantic outputs matched the locked baseline; validators exited 0.

The old evaluator wrapper and sealed v1 reservation are still unchanged at this point. The Core and Validation `parityBankSamples` methods are temporary migration oracles and must be removed after the wrapper switches and old Core experiment code is retired.
