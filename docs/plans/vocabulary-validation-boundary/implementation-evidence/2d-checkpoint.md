# Standalone wrapper transition checkpoint (2D)

The unchanged evaluator command path now builds the internal `LeafReaderValidation` module as a static library beside `LeafReaderCore`, both in the `LeafReader` package-access context and Swift 6 mode with warnings treated as errors. Causal and longitudinal script references now call the Validation bank evaluator. The old Core implementation remains temporarily for the final same-tree comparison and will be removed in 2E.

Verification:

- A clean isolated standalone build completed; `--causal-self-test` and `--longitudinal-self-test` exited 0.
- `swift test --filter VocabularyAssessmentBankParityXCTests -Xswiftc -warnings-as-errors`: 4 passed.
- The frozen [four-run 2D parity report](parity-2d.json), SHA-256 `8add0c8e380efcb7b71f3391514adbdb734c128db2ce37fa7dc78eea4aff05c1`, passed all 13 artifact comparisons and all report validators.
- `python3 scripts/check_validation_boundary.py`: passed; shipping App cannot reach Validation.
- Historical v1 reservation validator self-test: passed. The manifest remains byte-identical at SHA-256 `a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a` and `reservedNotExecuted`.

No product CAT equation, selector, stopping rule, report schema, command flag, or protected reservation was changed by this wrapper transition.
