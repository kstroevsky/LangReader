# Vocabulary runner extraction checkpoint (Commit 3)

The causal and longitudinal simulation, replay, forensic, manifest, provenance, metric, and report-encoding mechanics now live under `Sources/LeafReaderValidation/Vocabulary/`. The standard synthetic assessment generator, paired substreams, metrics, quality-gate calculation, and Markdown renderer also moved into Validation. The existing evaluator script remains the entry point but now owns argument validation, manifest reads, atomic artifact writes, printing, and exit status. All 29 recognized CLI flags and positional POS arguments remain unchanged.

Verification:

- Causal and longitudinal self-tests exited 0 after the module move and after file-I/O separation.
- `swift build --target LeafReaderValidation -Xswiftc -warnings-as-errors`: passed.
- `swift test --filter VocabularyValidationBankXCTests -Xswiftc -warnings-as-errors`: 8 passed.
- `swift test --filter VocabularyDiagnosticArtifactsXCTests -Xswiftc -warnings-as-errors`: passed; SHA-256 matches an independent known digest.
- `swift test --filter VocabularyAssessmentSyntheticRunnerXCTests -Xswiftc -warnings-as-errors`: passed against the frozen small-development semantic output hash.
- Frozen parity reports: [runner move](parity-3a.json) SHA-256 `812fe394d3be908d0d825fe47d8b978914b4dd5d86d3095d177a99a36597a332`; [thin file-I/O adapter](parity-3b.json) SHA-256 `93c4e036955719c9938d46be296c0f838aaede98183ef564095e54fdb20c3fec`; [standard runner move](parity-3c.json) SHA-256 `0dbc38c70a6fa33da54f94868278aa8379c3e308de72dab7a9f802c051eccccd`. Each passed the 13 frozen artifact comparisons and report validators.
- Candidate timing reports' `semanticReportSHA256` values matched their raw semantic JSON bytes. Timings remain separate measurement observations, not product latency claims.
- Final validation boundary check and historical v1 reservation self-test passed.

No production CAT implementation was copied. No experiment threshold, RNG stream, report schema, command flag, old reservation, or holdout was changed or consumed.
