# Post-extraction validation-boundary follow-up checkpoint

Status: **complete locally**. This follow-up resolves the three review findings against committed extraction head `5de7128feb8bc2cab2457d88d0fd7d88671654d9`. It does not approve a model candidate, analysis, human collection, confirmation execution, release-holdout access, or final-tree performance acceptance.

## Result

- The derived evidence register now retains v1/v2 as historical `reserved_not_executed`, identifies v3 as the sole active future reservation, indexes the extraction checkpoint and source lock as structural/provenance evidence, and reviews through generator commit `0dc16efd21e2816a5154b4d515c2b5272e6b8fe3`. Its scientific requirement records and status inventory are byte-structurally unchanged from the pre-follow-up register.
- Core no longer declares `diagnosticNaturalStopReason`, `diagnosticKnownProbability(for:)`, or `result(selectionOverride:)`. Existing production `result()`, `knownProbability(for:)`, and `VocabularyAssessmentResult.applyingSelection(_:)` provide the immutable facts/selection projection. Exactly one package-scoped experiment control remains: `nextQuestionForDiagnosticContinuation()`, used on Validation-owned assessment copies and guarded by the 80-answer ceiling, candidate exhaustion, exclusions, skips, and duplicate-answer protection. The boundary checker rejects reintroduction of the removed seams or a second/mis-scoped continuation seam.
- The versioned non-overlap corpus covers retained JSON under `docs/perf/`, `docs/plans/`, and `scripts/fixtures/` at the relevant seal commit. It includes earlier fixture/development seeds 1, 2, 7, 17, 20260909, 20260912, 20260913, and 20260914, release seeds, and v1/v2 identities. Opaque-document comparison conservatively scans every prior archived 24-hex JSON identity; v1 was the only earlier artifact using the exact derivation namespace at the v2 seal.
- v1 and v2 remain byte-identical and `reservedNotExecuted`. V2's historical validator distinguishes its original `b2b9969` provenance metadata from the exact post-extraction source-byte witness `5de7128`. V3 is sealed against clean generator-input commit `0dc16ef` and remains `reservedNotExecuted` with null candidate/analysis freezes and no outcome artifacts.

## Preservation evidence

The lossless follow-up revision is under `revision-2026-09-21-boundary-followup/`:

- locked base SHA-256: `55c2819200950f8c93a0d451bfe4659a4bc9bf5c0c1182086f28c89b95e8b879`;
- candidate SHA-256: `3a67d47ad1d0ea133618bff40611e9b40a8b6a3f1a5a7f7082f8210a80985cab`;
- mechanical verification: PASS, no warnings;
- semantic verification: PASS;
- independent forward verification: PASS after two bounded repair cycles;
- ledger: 67 active, 3 deferred, 3 superseded; zero unauthorized changes or removals.

## Source and reservation locks

| Artifact | SHA-256 | Status |
| --- | --- | --- |
| `parity-followup-2026-09-21.json` | `5aed1c6bf51b086cbe5bd476a489bbc88d48660287107322aa94631e92460704` | Four development runs / 13 artifacts PASS; no protected input. |
| `post-cleanup-generator-source-lock-v3.json` | `b11db3185cfb70c22115da15f82e554c1dda3e5553112a06c0bc95257975574a` | Binds generator commit `0dc16ef`; not a candidate/analysis freeze. |
| `development-confirmation-reservation-v1.json` | `a43e45a5fef43367b20e36e0f41684186901af325e2e597a994857591015303a` | Historical, `reservedNotExecuted`. |
| `development-confirmation-reservation-v2.json` | `19ccb4a9bddff02df1c074c85b56ffc782e7216d1a883a60cc088ac7338af89d` | Historical, `reservedNotExecuted`. |
| `development-confirmation-reservation-v3.json` | `8c25324b82cf54e7d1945ce2918c61d4eecae8522743839323e24edb58f7fb4c` | Sole active future set, `reservedNotExecuted`. |

No reserved seed or document identity was passed to an evaluator. No confirmation or release outcome was generated or inspected.

## Commits

- `850d09d72a40b584bf0bfe78337ce9708e1bdd8c` — review plan, register synchronization, and historical-v2/all-prior validator hardening.
- `0dc16efd21e2816a5154b4d515c2b5272e6b8fe3` — remove three Core controls, retain/test the one guarded continuation seam, and record frozen development parity.
- `ed92bb31db7a64048076bd83d56233f00a310404` — seal v3, update current pointers/register, and wire all three reservation checks.

Earlier extraction history was not rewritten.

## Verification

| Command | Result |
| --- | --- |
| `python3 .../plan_guard.py verify ...` | PASS; no errors/warnings. |
| `swift test --filter AdaptiveVocabularyAssessmentXCTests -Xswiftc -warnings-as-errors` | 41 passed. |
| `swift test --filter VocabularyAssessmentObservationXCTests -Xswiftc -warnings-as-errors` | 5 passed, including continuation hard guards on a copied assessment. |
| `python3 scripts/check_validation_boundary.py --self-test --final` | PASS; dependency/type/method negative fixtures passed. |
| `python3 scripts/check_vocabulary_extraction_parity.py ...` | PASS across 13 development artifacts. |
| v1/v2/v3 reservation validator self-tests | All PASS, including mismatch/missing-lock and unavailable-history controls. |
| `./scripts/check.sh --no-build` | PASS; strict Swift build, 177 Swift tests (1 skip), 281 logic tests, and all deterministic/evidence checks. |
| `./scripts/build_app.sh` | PASS; app built, signed, validated on disk, and satisfied its designated requirement. Optional bundled speech runtimes were absent, so this is not a bundled-runtime release check. |
| `git diff --check` | PASS. |

Remote Architecture CI at `5de7128` remains red on the same German participle/NaturalLanguage assertion reported at baseline `b2b9969`; the extraction-specific boundary, strict build, and Swift tests passed before that failure. These follow-up commits have not been pushed, so remote CI has not run them. This pre-existing CI issue remains separate from the completed boundary follow-up.

Performance impact was not measured and no performance improvement is claimed. The remaining gates are independent statistical/research/privacy review, a later clean candidate and analysis/decision-rule freeze, a separate reviewed decision before one-time v3 consumption, the release holdout, and frozen-final-tree algorithm/private-GUI performance evidence.
