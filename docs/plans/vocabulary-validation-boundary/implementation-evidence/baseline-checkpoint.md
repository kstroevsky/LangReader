# Extraction baseline checkpoint

Source revision: `b2b99696feda177be0699d5277a2c13c7c7c9bd5`. Tracked `Sources`, `Tests`, `scripts`, `Package.swift`, and `.github/workflows/architecture.yml` were clean before source edits; the plan documents were untracked. Swift: Apple Swift 6.0.3, arm64 macOS target.

The immutable [extraction-parity manifest](extraction-parity-manifest.json) was frozen before source edits at SHA-256 `a1c2d778a0fcf90357c3b7cc0e3d0db68e414f57f94c8bc39ffdef68a0a68b1b`. It names four authorized development runs, their exact commands/inputs/exit statuses, 13 output hashes, and the only source-provenance fields eligible for canonicalization. Timing JSON is retained separately, not used to excuse semantic differences.

The standard, causal, longitudinal, and selected POS development runs all exited 0. The assessment, causal, longitudinal, POS, and sealed-reservation validators passed. Causal and longitudinal self-tests passed. The tiny synthetic assessment runs include adverse quality rows and are gate-ineligible; none was used for tuning. No sealed development-confirmation run, release holdout, consumed POS held-out scoring, or human collection was accessed.

The baseline evaluator and POS executables were built in isolated `.build/` directories. After the new target scaffold, `swift build --product LeafReaderApp -Xswiftc -warnings-as-errors` and `swift test --filter ValidationBoundaryXCTests -Xswiftc -warnings-as-errors` passed; the standard evaluator JSON/Markdown remained byte-identical to the baseline. The historical reservation manifest hash remains `a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a`.

CI has not run remotely. The local Architecture checkout change makes history available with `fetch-depth: 0`; the historical validator self-test passes against the recorded Git revision and rejects injected bytes/checksum/path/revision mismatches without altering Git objects.
