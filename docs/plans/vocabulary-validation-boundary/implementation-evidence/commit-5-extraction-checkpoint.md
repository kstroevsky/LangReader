# Validation-boundary extraction checkpoint (Commit 5)

Status: structural extraction complete at the uncommitted implementation checkpoint based on `b2b99696feda177be0699d5277a2c13c7c7c9bd5`. This is **not** a clean candidate, analysis, or release freeze. The accepted plan is `../revision-2026-09-19-ci-source-lock/candidate-plan.md` (SHA-256 `55c2819200950f8c93a0d451bfe4659a4bc9bf5c0c1182086f28c89b95e8b879`). Its historical source lock was not refreshed.

## Behavior and ownership

- The shipping `LeafReaderApp` product still reaches only `LeafReaderCore`. `LeafReaderValidation` is an internal, non-product SwiftPM target that depends on Core, never App. The negative-fixture architecture check enforces target dependencies, imports, shipping closure, and removal of migrated production declarations.
- Core owns immutable production assessment observation and selection semantics. Validation owns A/B1/B2 and fixed-bank counterfactuals, synthetic/causal/longitudinal/POS execution, report construction, and study schemas. Existing shell/Swift command paths remain thin adapters with the same CLI surface.
- PDF/EPUB/DOCX extraction integration stays in App tests. The historical v1 reservation remains byte-identical, sealed, and unexecuted; the new v2 set is a separate active **future** reservation with 3 disjoint run identities and 24 opaque document identities. Neither set was scored.
- No production thresholds, sample counts, RNG derivations/consumption, question/deck/evidence/posterior semantics, report schemas, or native reader seams were changed. No scientific gate was advanced.

## Frozen and current provenance

| Artifact | SHA-256 | Role |
| --- | --- | --- |
| `extraction-parity-manifest.json` | `a1c2d778a0fcf90357c3b7cc0e3d0db68e414f57f94c8bc39ffdef68a0a68b1b` | Frozen before source edits; exact commands, inputs, expected exits, 13 baseline artifact hashes, and allowed provenance/timing differences. |
| `parity-4.json` | `08121ebcb973f93b5c4c3c09d6bbb9dfe71303046760f6c63452e0a11f0a951f` | Final four-run development-fixture parity report, PASS. |
| `extracted-generator-source-lock.json` | `ba1383065f79f3b43f87b3fa69d3916133b683b5d7f2615465c45e41502abd38` | Current dirty-tree Core/Validation source and standalone-build input lock; Swift 6 flags and analysis provenance, not an analysis freeze. |
| Historical `development-confirmation-reservation-v1.json` | `a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a` | Original Git-blob-verified, `reservedNotExecuted` evidence. |
| Fresh `development-confirmation-reservation-v2.json` | `19ccb4a9bddff02df1c074c85b56ffc782e7216d1a883a60cc088ac7338af89d` | New source-locked, `reservedNotExecuted` identities; no candidate/analysis/outcome fields populated. |

The parity report includes 7 byte-equal artifacts (standard, embedded standard, POS), 4 causal/longitudinal artifacts equal after removing only the predeclared source-provenance fields/lines, and 2 raw timing artifacts retained but not used to excuse semantic differences. The canonical JSON comparisons include every question, evidence, posterior, classification, stopping, deck, and mask field; the 2B–2E same-tree parity checkpoints additionally compare theta positions and mask words. All four evaluator commands and report validators exited 0. No protected confirmation/release/POS-held-out case or human data was used; the development-fixture outputs are not release evidence.

## Commands and exit status

| Command | Exit | Result |
| --- | ---: | --- |
| `python3 scripts/check_vocabulary_extraction_parity.py --output-dir .build/vocabulary-extraction-parity-4 --report docs/plans/vocabulary-validation-boundary/implementation-evidence/parity-4.json` | 0 | Four development runs, 13 artifacts; PASS at frozen hash above. |
| `python3 scripts/check_validation_boundary.py --self-test --final` | 0 | Production-to-Validation and Validation-to-App negative fixtures rejected. |
| `python3 scripts/validate_vocabulary_development_confirmation_reservation.py --self-test` | 0 | Historical Git-object seal and injected mismatch controls passed. |
| `python3 scripts/validate_vocabulary_development_confirmation_reservation_v2.py --self-test` | 0 | Fresh derivation, non-overlap, lock, premature-outcome, and missing/mismatched-lock controls passed. |
| `swift build -Xswiftc -warnings-as-errors` | 0 | Strict Swift 6 build passed. |
| `swift test -Xswiftc -warnings-as-errors` | 0 | 176 tests; 1 existing skip; 0 failures. |
| `./scripts/check.sh --no-build` | 0 | Full deterministic checks, including 281 logic tests, evidence validators, original/fresh reservations, and generated-wiki check; final rerun said `All checks passed.` |
| `./scripts/build_app.sh` | 0 | App built, signed, and validated on disk. Optional bundled speech runtimes were absent, so this is not a bundled-runtime release check. |
| `git diff --check` | 0 | No whitespace errors. |

The first `./scripts/check.sh --no-build` after adding the v2 validator stopped because generated `docs/wiki/code-map.md` was stale. `./scripts/generate_code_wiki.sh` refreshed the local generated map/index, `./scripts/check_wiki.sh` passed, and the definitive full rerun above exited 0. No remote CI run or GUI smoke test was performed.

## Changed-file scope

The owned implementation edits are `Package.swift`, `.github/workflows/architecture.yml`, Core's `AdaptiveVocabularyAssessment.swift` and new `VocabularyAssessmentObservation.swift`, the eight `Sources/LeafReaderValidation/Vocabulary/*.swift` files, corresponding Core/Validation tests, and the evaluator/validator/build/check scripts under `scripts/`. Prior Core experimental bank/study files and large standalone Swift runner bodies were removed after their counterparts were moved into Validation. `docs/architecture/DESIGN.md`, `Validation/Vocabulary/CURRENT.md`, and generated `docs/wiki/{code-map,type-index}.md` reflect the implemented boundary. New baseline, parity, source-lock, state, and slice-checkpoint files are under this implementation-evidence directory; the new v2 reservation is in the existing evidence archive. The unrelated untracked `.trigger-tree/` directory was preserved and excluded from this work.

## Stop line

No commit or remote push was made. Performance impact was not measured, and no improvement is claimed. Remaining work is independent statistical/research/privacy review, a clean candidate plus analysis/decision-rule freeze with fresh hashes, a separate reviewed decision to consume v2 exactly once, then the later release-holdout and frozen-final-tree algorithm/private GUI timing gates. Any relevant generator edit invalidates this source lock; do not silently rehash v2 or use v1's historical identities.
