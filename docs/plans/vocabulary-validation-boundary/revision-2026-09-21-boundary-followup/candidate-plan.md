# LeafReader validation boundary and remaining-gates implementation plan

## Status and authority

[AUTH-001] This follow-up candidate is derived from the user-accepted extraction plan, preserving its requirements except the review deltas below. The user's “Continue” authorizes this bounded structural follow-up, including the v2-to-v3 reservation route and one narrow continuation exception. It does not authorize data collection, a confirmation run, release-holdout access, a candidate/analysis freeze, or a production model-policy change.

[AUTH-002] The authoritative product and scientific contracts remain the hash-locked vocabulary roadmap, its target ledger, the current evidence-status register, the sealed reservations, and the review-readiness artifacts. Candidate extraction-plan source lock: `docs/plans/vocabulary-validation-boundary/revision-2026-09-19-ci-source-lock/source-lock.json`, SHA-256 `12944c83d2bdf0423b89333457030140618c4c70ffd9e6909d4560cbc249e5ba`. The older `docs/plans/vocabulary-validation-evidence/verification/source-lock.json` is a different historical lock and does not define this extraction plan's inputs. This plan schedules and constrains a structural extraction; it does not amend the underlying product or scientific contracts.

[AUTH-003] The original pre-extraction starting revision remains a historical fact: the accepted extraction started from clean `b2b99696feda177be0699d5277a2c13c7c7c9bd5`, with its immutable baseline lock and parity manifest. The post-extraction follow-up starts from committed `5de7128feb8bc2cab2457d88d0fd7d88671654d9`; its changed generator receives separate provenance and a new reservation under `LOCK-007`. Neither earlier lock is refreshed to match a later tree.

## Decision and acceptance criteria

[GOAL-001] The goal is worthy: production code, correctness tests, model-validation experiments, and human-research evidence must have visibly different owners and dependency directions. The benefit sought is comprehensibility, containment of research concepts, safer evidence evolution, and reviewability of what ships; cross-feature reuse is optional.

[GOAL-002] The necessary architecture is a one-way boundary between shipping behavior and validation behavior. The current shared Swift machinery is substantial enough to justify one internal `LeafReaderValidation` target, but not a separate package, repository, public SDK, or framework ecosystem.

The extraction is accepted only when all of the following are true:

- [AC-001] LeafReader's shipping product still consists only of `LeafReaderApp` and `LeafReaderCore`, with unchanged user-visible behavior and production semantics.
- [AC-002] Validation executes the production assessment, vocabulary-index, coverage/deck, prior, and difficulty implementations; it does not copy their equations or policies.
- [AC-003] Experiment concepts are absent from App-facing and production-facing APIs except for a package-scoped, immutable Core observation surface that exposes production facts and exactly one package-scoped continuation primitive, `nextQuestionForDiagnosticContinuation()`. Validation may call that primitive only on its isolated assessment copy for fixed-budget diagnostics; it must retain the 80-answer ceiling, candidate exhaustion, exclusions, skips, and duplicate-answer protection, and the App must never call it. Remove `diagnosticNaturalStopReason`, `diagnosticKnownProbability(for:)`, and `result(selectionOverride:)` from Core; obtain their needed facts from immutable production results/observations without changing product question selection or stopping.
- [AC-004] Deterministic runner outputs and frozen-fixture decisions match the pre-extraction baseline under the parity rules below.
- [AC-005] Historical evidence remains immutable, existing reservations remain sealed, and no scientific or release gate is reordered.
- [AC-007] The existing development-confirmation reservation stays `reservedNotExecuted` as immutable historical evidence; its seeds are not rebound. After extraction and parity, a fresh disjoint seed/document set against the extracted generator is sealed as the active future reservation before any candidate freeze. The original manifest is never rewritten.
- [AC-008] The v2 set fulfilled `AC-007` at the extraction checkpoint; the post-extraction Core cleanup then changes its generator source lock. Preserve v1 and v2 byte-for-byte as `reservedNotExecuted` historical reservations, without rebinding their identities. After development-fixture parity on the changed generator, seal a fresh disjoint v3 seed/document set and source/build lock as the sole active future reservation; neither v2 nor v3 may be scored by this follow-up.
- [AC-006] The dependency check, strict Swift build/tests, deterministic repository suite, and development app assembly all pass.

## Target architecture

[ARCH-001] Add one internal SwiftPM library target named `LeafReaderValidation`, rooted at `Sources/LeafReaderValidation`, and one corresponding `LeafReaderValidationTests` target. Do not add `LeafReaderValidation` as a library product and do not add it to the shipping app product.

```text
LeafReaderApp --------------------> LeafReaderCore
                                         ^
                                         |
LeafReaderValidation --------------------+
        ^
        |
validation executable/scripts

LeafReaderCore -X-> LeafReaderValidation
LeafReaderApp  -X-> LeafReaderValidation
shipping app   -X-> LeafReaderValidation
```

[ARCH-002] `LeafReaderValidation -> LeafReaderCore` is the only allowed production-code dependency involving the validation target. `LeafReaderCore` and `LeafReaderApp` must neither import nor declare a target dependency on `LeafReaderValidation`. Test targets may depend on `LeafReaderValidation` when testing validation-owned helpers; for example, `LeafReaderValidationTests -> LeafReaderValidation + LeafReaderCore` and, if useful, `LeafReaderAppTests -> LeafReaderValidation`. Those test-only edges must not enter the shipping `LeafReaderApp` product closure, and `LeafReaderValidation` itself must never depend on `LeafReaderApp`.

[ARCH-003] `LeafReaderValidation` is repository-internal infrastructure: no semantic-version promise, external product, public SDK design, or cross-repository lifecycle is introduced.

[ARCH-004] Use `Sources/LeafReaderValidation/Vocabulary/` for vocabulary-specific execution and evaluation code. A top-level `Validation/Vocabulary/CURRENT.md` may serve as a short, non-authoritative pointer to current hash-locked protocols and evidence; it must not duplicate or replace their normative payloads.

[ARCH-005] Preserve existing script entry paths and flags during the extraction. Scripts become thin composition/orchestration adapters around Core plus `LeafReaderValidation`; changing the CLI is a separate future decision.

## Ownership classification

[OWN-001] `LeafReaderCore` continues to own the single production implementation of `AdaptiveVocabularyAssessment`, its model configuration, knowledge and observation semantics, question selection, cross-moment scoring, coverage sampling, deck construction, stopping, `VocabularyReaderPrior`, difficulty behavior, and the document vocabulary inventory/index.

[OWN-002] Keep a package-scoped, immutable `VocabularyAssessmentDiagnosticSnapshot`-style carrier in Core because it describes observable production state. Each item exposes only canonicalKey, occurrenceCount, isIncluded, evidence, responseCurve, and productionKnownMask—not a full `DocumentVocabularyCandidate`. Preserve the production selection, masks/strata, and fingerprints as observed facts. Keep posterior, epsilon knowledge, reliability scale, and theta positions private where possible; expose only narrow immutable values or operations intentionally required by Validation's evaluator. Do not expose a generic mutable/native escape hatch or enough unrelated candidate state to construct an alternate production assessment. Snapshot construction must not mutate caches, consume additional shared random-stream state, alter stopping, or change the next question.

[OWN-008] Split the current mixed `VocabularyDiagnosticInputError` alongside the snapshot split: Core may retain only errors required to construct or observe production facts, while bank-specific cases such as `incompatibleB1SampleCount` move with the A/B1/B2 evaluator to Validation. Preserve equivalent rejection behavior and test it on both sides of the boundary; do not make Core import a Validation error type.

[OWN-009] Remove the experimental `selectionOverride:` parameter from Core's `AdaptiveVocabularyAssessment.diagnosticSnapshot`. Its selection must always be the production-selected set. Counterfactual selected-set evaluation belongs in Validation against that immutable snapshot, using the existing evaluator's `selectedKeys:` concept or an equally narrow Validation-owned operation. Preserve current counterfactual outputs and reject unknown or excluded override keys as before.

[OWN-003] Move experimental interpretation out of Core: A/B1/B2 bank kinds and configuration, independent-bank generation/evaluation, fixed-bank controls, synthetic truth and responses, experiment arms, confirmation experiments, forensic cases, replay/counterfactual orchestration, longitudinal histories, validation manifests, experiment reports, and reservation-aware runner mechanics belong to the validation subsystem. Their reusable Swift execution portions move to `LeafReaderValidation`; Python orchestration, statistical analysis, schema validation, and thin script entry points may remain under `scripts/`. Frozen manifest/report files stay in the immutable evidence archive; this is not a mandate to rewrite reservation machinery in Swift.

[OWN-004] Move `VocabularyValidationStudyDataset.swift`, `VocabularyValidationStudyPackageV2.swift`, and their validation-specific tests to the validation target. Their Codable shapes, validation rules, and serialized bytes remain unchanged.

[OWN-005] Keep `VocabularyPredictionAudit` and `VocabularyResearchExport` in Core for this extraction because the shipping App currently consumes them. Removing or redesigning those product flows would be a separate product decision and must not be smuggled into this refactor.

[OWN-006] Swift owns faithful execution of production behavior: assessment runs, synthetic answers, deck construction, prior-store histories, replay, diagnostics, and evidence capture. Python continues to own aggregation, statistical fitting, DIF/study analysis, report comparison, and schema validation. The first extraction does not relocate Python merely for directory symmetry.

[OWN-007] Correctness tests remain beside their implementation owners. Algebra parity, deterministic deck ordering, prior-store persistence, model arithmetic, and App coordination tests stay in Core/App test targets. `VocabularyPreparationFixtureXCTests` remains in `LeafReaderAppTests` because it exercises real PDFKit/Web/document-loading and final vocabulary-pipeline integration across PDF, EPUB, and DOCX. That test target may depend on `LeafReaderValidation` if it calls a shared Validation comparison helper, without adding Validation to the App product. Tests move to `LeafReaderValidationTests` only when the behavior under test moves to `LeafReaderValidation` or is explicitly an experiment-quality claim; Validation never depends on App merely to absorb an integration test.

## Evidence preservation and parity

[EVID-001] Validation software is maintainable and refactorable; protocols, source locks, frozen reports, failed-candidate evidence, consumed holdouts, experiment checkpoints, reservations, approvals, and old protocol versions are immutable historical evidence.

[EVID-002] Do not move or rewrite the existing archive under `docs/plans/vocabulary-validation-evidence/` or the existing performance evidence under `docs/perf/`. New navigation may point to them by repository-relative path and SHA-256. Any future archive relocation requires a separate migration with link and checksum preservation.

[EVID-003] Refresh the authoritative derived evidence-status register from its source spec: index v1 and v2 as historical `reserved_not_executed`, v3 as the sole active future `reserved_not_executed` reservation, and the extraction checkpoint plus source lock as structural/provenance evidence only. Set `repository_head_reviewed` to the actually reviewed committed extraction/follow-up head, retain all earlier artifact hashes, and leave every scientific requirement record, status count, and gate unchanged. The register must not convert extraction parity or a reserved identity into scientific validation.

[PAR-001] The extraction must not change any existing seeds, RNG stream derivation or consumption, algorithms, equations, thresholds, evidence reliabilities, question ordering, stopping, experiment definitions, sample counts, report schemas, field names, encodings, command flags, reservation semantics, or checksums of historical evidence. The later fresh reservation creates separately sealed new seeds/documents; it does not mutate or reuse any earlier reservation.

[PAR-002] Build the pre-extraction and post-extraction runners and execute both against the same authorized fixtures and manifests. Require byte-identical deterministic JSON/Markdown and identical exit status where source/path-independent. For fields whose contract is truthful source identity or wall-clock timing, retain both raw artifacts and compare all remaining fields after a predeclared canonicalization that removes only those fields; do not normalize metric values, seeds, identifiers, decisions, missingness, or failure records.

[PAR-003] Existing evaluator, causal, longitudinal, POS, and validator entry paths remain callable with the same arguments. Existing JSON remains decodable by current validators; frozen fixtures remain accepted or rejected exactly as before. Golden or schema updates cannot be used to make a parity failure pass.

[PAR-004] Before any source edit, freeze one machine-readable extraction-parity manifest for this finite migration. It enumerates the exact authorized baseline commands and input paths/hashes, expected exit statuses observed at baseline, output artifact paths/hashes, source/configuration identity, and the specific source-identity or wall-clock fields predeclared for canonicalization. The post-extraction comparison reads that immutable manifest; it cannot silently replace inputs, drop failed runs, add normalized metric fields, or rewrite expectations after seeing results. It does not reserve or score any protected holdout.

[DATA-001] Baseline and parity scoring runs may use ordinary development fixtures and existing self-tests only. They must not score the sealed development-confirmation reservation, the release holdout, consumed POS held-out cases, or any human collection path. Existing deterministic validators may read the already-consumed POS fixture and report solely to verify historical integrity; this does not make those cases fresh development material or permit new predictions, tuning, or candidate comparisons on them.

[DATA-002] Verify v2 and v3 seed non-overlap against the versioned corpus of all prior repository-retained development, confirmation, and release seed-bearing JSON artifacts under `docs/perf/`, `docs/plans/`, and `scripts/fixtures/`, not just two named development seeds. Compare opaque document identities conservatively against every prior archived 24-hex identity in that corpus; at the v2 seal only v1 used that exact opaque-document namespace. Record the corpus revision and fail on unavailable history or missing/mismatched source evidence. This check reads identities only; it does not run a generator, score outcomes, or grant holdout access.

## Sealed generator-lock compatibility checkpoint

[LOCK-001] `development-confirmation-reservation-v1.json` pins SHA-256 values for `scripts/evaluate_vocabulary_assessment.sh`, `scripts/evaluate_vocabulary_assessment.swift`, `scripts/vocabulary_assessment_causal_diagnostics.swift`, and the canonical gate ledger. Its current validator checks the files at those repository paths, and `scripts/check.sh` runs that validator. Moving the pinned Swift implementation or changing the shell wrapper therefore breaks the seal check even if evaluator outputs remain identical. Report parity alone cannot repair this source-identity mismatch.

[LOCK-002] The selected route is a fresh post-extraction development-confirmation reservation, not additive rebinding of the old seed/document set. The original reservation remains `reservedNotExecuted` with its original generator lock and no inspected outcomes. Before editing pinned generator files or removing Core declarations required by the historical runner, the revised plan must be accepted and the historical validator migration in `LOCK-003` must pass. Never modify the original manifest to make its hashes match current files.

[LOCK-003] Preserve the original manifest byte-for-byte and migrate its validator to verify pinned generator bytes from the recorded Git revision, not mutable current paths. Prove the original self-test remains green before and after pinned-file movement, including a negative control using mismatched historical bytes/checksum, path, or revision; do not corrupt the Git object database. Historical revisions required by any source lock must be available in the Architecture CI checkout before `check.sh` invokes the validator. Missing historical Git objects are an infrastructure failure, not a generator-lock mismatch. At the extraction checkpoint, the historical check and extracted-generator provenance must pass; no future-reservation validator is required before its reservation exists. After extraction is complete and development-fixture parity passes, create and freeze a fresh disjoint seed/document reservation against the extracted generator, locking its current source paths/hashes, transitive Core/Validation build inputs, Swift 6 flags, analysis binding, and no-outcome status. From creation onward, the new-reservation validator must fail on a missing or mismatched lock and be green before candidate freeze; no outcome access is allowed until candidate/analysis freeze and a separate reviewed consumption decision. The earlier additive-rebinding option is not authorized for this extraction.

[LOCK-007] For this post-seal follow-up, keep the v2 manifest and source lock immutable. Its `reservationBaseRevision`/`sourceRevision` fields name the original `b2b9969` baseline, not the post-extraction generator bytes; the independently matched sealed source-byte witness is commit `5de7128feb8bc2cab2457d88d0fd7d88671654d9`. Verify the v2 source tree and locked paths from that Git commit, distinguishing unavailable objects from mismatched bytes; do not make changed current sources pass by rehashing v2. After Core cleanup, re-run the frozen development-fixture parity contract, then lock the changed Core/Validation/build inputs and create the fresh disjoint v3 reservation with no outcomes or candidate/analysis freeze. The evidence register and `CURRENT.md` must identify v1/v2 as historical unexecuted and v3 as the sole active future reservation. The v3 validator must reject missing or mismatched current generator inputs; no reservation is consumed in this follow-up.

[LOCK-004] Until the fresh route is accepted and the historical Git-blob validator is green, the extraction may proceed only in nonconflicting slices. Do not edit the pinned runner, evaluator, or causal-support paths, nor remove Core APIs that the frozen runner needs. If the validator cannot preserve the historical seal, stop and report a partial extraction rather than weakening `check.sh` or claiming completion.

[LOCK-005] The current evaluator and POS shell wrappers compile standalone Swift with `swiftc` and link only `libLeafReaderCore.a`; a new SwiftPM target is not automatically available to them. In the approved route, explicitly build/link `LeafReaderValidation` in the same package-access context, Swift 6 mode, optimization mode, and warnings-as-errors regime, or use an equivalent proven invocation. Preserve existing wrapper paths, flags, exit behavior, and deterministic artifacts; test a clean build with no cached modules.

[LOCK-006] The extraction-plan source lock is `docs/plans/vocabulary-validation-boundary/revision-2026-09-19-ci-source-lock/source-lock.json`, SHA-256 `12944c83d2bdf0423b89333457030140618c4c70ffd9e6909d4560cbc249e5ba`; it is a historical baseline lock for the clean `b2b99696feda177be0699d5277a2c13c7c7c9bd5` source tree and the attached user brief, not `docs/plans/vocabulary-validation-evidence/verification/source-lock.json`. After extraction, verify repository entries against the recorded Git tree and the external brief against its locked attachment bytes, not against current edited repository paths; record a separate current-candidate source/build lock. Do not refresh the baseline lock to make changed files match. A changed starting tree before implementation requires a newly reviewed baseline and plan delta, while an expected implementation edit requires current-candidate provenance.

## Implementation sequence

[IMPL-001] The Commit 1–5 sequence below records the completed extraction and its retained checkpoints, not work to replay during this follow-up. Its original ordering, historical Git-blob prerequisite, and stop-on-failure obligations remain authoritative for interpreting that evidence. Do not combine this follow-up with model experimentation. Execute only the bounded post-extraction steps in `FOLLOW-001` below.

[MIG-001] The LOCK controls, parity manifest, and source-transition checks are finite migration controls, not permanent product architecture. Keep their frozen records for audit, but expire the exact old-Core evaluator allowance at 2E and remove any temporary code path after parity. The enduring state is the one-way target boundary, owner-aligned tests, thin scripts/Python analysis, immutable evidence archive, and short `CURRENT.md` pointer—not an ongoing migration framework.

### Baseline checkpoint — no source changes

1. Record the starting commit, dirty state, Swift version, package graph, relevant source hashes, CLI help/flags, and historical evidence hashes.
2. Build the existing evaluator/POS executables in an isolated build directory.
3. Capture authorized self-test and small development-fixture outputs, raw timing/provenance, exit statuses, and validators.
4. Record the exact normalization rule for unavoidable timing/source-identity differences before seeing post-extraction output.
5. Freeze the `PAR-004` manifest before editing source, then verify the sealed generator hashes at their current paths and record acceptance of the selected fresh route before scheduling any pinned-file edit.

### Commit 1 — target scaffold and boundary

1. Add `LeafReaderValidation` and `LeafReaderValidationTests` to `Package.swift` without adding a product or App dependency.
2. Add the dependency-direction check and its negative fixtures first.
3. Add the short `Validation/Vocabulary/CURRENT.md` pointer without moving evidence.
4. Prove that a no-content target scaffold does not alter the app product or baseline runner behavior.
5. Prove an isolated Swift 6 build/link path for Validation code without changing the pinned runner wrapper before the binding decision is effective.
6. Migrate the historical reservation validator to verify its original generator bytes from the recorded Git revision; prove its self-test and injected historical-lock mismatch controls before any pinned-file edit. Keep the original reservation unchanged and unexecuted.
7. Make the locked historical revision available to the Architecture CI checkout before `./scripts/check.sh --no-build`, using `fetch-depth: 0` or an equivalently deterministic explicit fetch. Verify the validator in a CI-like checkout; absence of the historical object must be reported as infrastructure failure.

### Phase 2 — staged schemas and diagnostic extraction

Each subcommit below must pass the narrow affected tests and the existing evaluator self-test before the next begins. Temporary duplication is permitted only for validation-only bank evaluation during 2B–2D. Never duplicate `AdaptiveVocabularyAssessment`, its production equations, selection, stopping, or deck policy.

#### 2A — move independent study schemas and tests

Move `VocabularyValidationStudyDataset.swift`, `VocabularyValidationStudyPackageV2.swift`, and their validation-specific tests to Validation. Preserve declarations, Codable shapes, validation rules, serialized bytes, and privacy rejection behavior, changing access only where the in-package target boundary requires it. The old evaluator wrapper remains unchanged and green.

#### 2B — introduce the narrow Core observation and parallel Validation evaluator

Introduce the narrowed immutable Core production-fact snapshot and Core-only construction errors alongside the old Core diagnostic implementation. Add the new A/B1/B2, fixed-bank, and selected-set evaluator in Validation with bank-specific errors, calling the same production knowledge and observation semantics. Give it only the read-only package-scoped facts it needs; the old wrapper still links the old Core evaluator, and both implementations compile in the same tree.

#### 2C — prove old-versus-new A/B1/B2 and counterfactual parity

Run both bank evaluators on identical assessment states and selected sets in the same source tree. Require exact production-A/B1/B2 masks, theta positions, fingerprints, coverage/quantile/miss outputs, counterfactual results, and invalid-input rejection; retain adverse and null cases. Prove snapshot observation leaves result, stop state, and future question path unchanged. Do not switch the wrapper or delete old code until this comparison passes.

#### 2D — switch the evaluator wrapper and script linkage

With `LOCK-003` historical validation already green and 2C parity proven, update the pinned evaluator wrapper and causal/longitudinal script imports to build/link Validation beside Core in the same package-access, Swift 6, optimization, and warnings-as-errors context. Preserve command paths, flags, exit statuses, schemas, deterministic artifacts, and a clean no-cache build. The old Core bank implementation remains available only as a temporary parity reference in this slice.

#### 2E — remove the old Core experiment implementation

Remove the old Core A/B1/B2 evaluator, fixed-bank interpretation, bank-specific errors, and the experimental `selectionOverride:` knob, leaving only the new narrow production-fact observation seam and Core-only construction errors. Move or update affected tests with their owners. Prove no causal/longitudinal script still depends on removed Core bank symbols; run the integrated evaluator self-test, strict build/tests, and full parity comparison before closing the slice.

### Commit 3 — assessment, causal, and longitudinal runners

1. Move shared synthetic reader/truth/response, paired substream, replay, forensic, manifest, report, provenance, and metric mechanics from the large Swift scripts into `LeafReaderValidation/Vocabulary/`.
2. Keep evaluator command parsing and file I/O as thin adapters with unchanged flags and exit behavior.
3. Retain the 2D wrapper/import/link integration while moving runner internals; verify a clean build without relying on an old cached Core or Validation module.
4. Compare old and new outputs on every locked baseline case before deleting duplicate script-local code.

### Commit 4 — POS and cross-format validation helpers

1. Move reusable Swift POS evaluation and cross-format comparison mechanics into the validation target only where they need Core rather than App. Leave the real PDFKit/Web/document-loading fixture and integration assertions in `LeafReaderAppTests`; those tests may call a shared Validation comparison helper if useful, but `LeafReaderValidation` must not depend on `LeafReaderApp`.
2. Keep production lexical identity, occurrence accounting, vocabulary inventory, parsing, and objective implementations in Core.
3. Keep Python statistical/reporting validators in their current role and use only fresh development POS material for new scoring or tuning; allow the existing read-only historical-integrity validator, but do not produce new predictions or candidate comparisons on the consumed held-out POS set.

### Commit 5 — enforcement, documentation, and stop

1. Wire the dependency-direction check and validation tests into `scripts/check.sh`.
2. Verify existing script compatibility, evidence paths, the immutable historical baseline lock against recorded Git blobs, extracted-generator source/build provenance, and deterministic report parity. The fresh active reservation is created only after the extraction checkpoint passes.
3. Update the concise architecture document and `CURRENT.md` only with the boundary that was actually implemented.
4. Run the full verification matrix below, publish the extraction checkpoint, and stop. Do not redesign the assessment, introduce a new safeguard, or start the deferred generalization/CLI work.

## Post-extraction review follow-up

[FOLLOW-001] Execute these slices in order, retaining a green checkpoint before the next slice:

1. Refresh the derived register's source spec and generated register, and harden v2's historical identity/source-lock validator without changing the v1/v2 manifests or their locks.
2. Remove the three named Core diagnostic controls, retain exactly the guarded package-scoped continuation primitive on a Validation-owned assessment copy, and prove production behavior and development-fixture parity unchanged.
3. Commit the changed generator, seal fresh disjoint v3 identities and its current source/build/analysis-provenance lock, and make v3 the sole active future reservation in the derived register and `CURRENT.md`. Do not run any reserved set.
4. Run strict Swift tests, the deterministic repository suite, app assembly, historical/current reservation negative controls, and final parity; report remote CI separately from local evidence and do not rewrite earlier commits.

## Verification

[VER-001] Narrow tests must cover: Core snapshot immutability, its exact minimal item-field shape without `DocumentVocabularyCandidate`, production-selection identity, Core-only construction errors, and next-question parity; Validation-only selected-set counterfactual parity including unknown/excluded-key rejection; production-A parity; B1 strata, latent-stream behavior, and bank-specific error rejection; B2 independent theta/latent behavior; fixed-bank and mass-conservation controls; validation-study schema round trips and privacy rejections; causal/longitudinal/POS self-tests; and unchanged App coordination for the Core-owned prediction-audit/research-export flows. The follow-up additionally verifies the continuation seam's 80-answer ceiling and other hard guards, removal of the other three Core diagnostic controls, identical development-fixture semantics, historical v2 lock rejection controls, versioned all-prior identity checks, unchanged scientific register statuses, and the unexecuted v3 current-source lock.

[VER-002] The hard architecture check parses the SwiftPM target dependency graph, source imports, and shipping-product link closure. It fails if the production `LeafReaderCore` or `LeafReaderApp` target depends on/imports Validation, if the shipping `LeafReaderApp` product reaches Validation transitively, or if explicitly enumerated migrated validation-only module/type declarations remain in production after 2E. Test-target dependencies on Validation are permitted and checked separately so `LeafReaderAppTests` can use Validation-owned helpers without changing the shipping closure; `LeafReaderValidation -> LeafReaderApp` remains forbidden. During 2B–2D, only the exact old Core bank declarations needed for same-tree parity may have a time-bounded migration allowance that expires at 2E. The broader vocabulary/name scan is advisory or narrowly declaration-scoped with an explicit reviewed allowlist; comments, unrelated future features, and ordinary diagnostic words must not fail the build.

[VER-003] Run, at minimum, the affected strict Swift tests while iterating, then `swift build -Xswiftc -warnings-as-errors`, `swift test -Xswiftc -warnings-as-errors`, `./scripts/check.sh --no-build`, and `./scripts/build_app.sh`. Package/app assembly is in scope because `Package.swift` changes even though UI behavior does not. The Architecture workflow must make every historically locked revision reachable before `check.sh`: prefer `actions/checkout@v4` with `fetch-depth: 0`, or an equivalently deterministic explicit fetch of the locked revision. This is a prerequisite of the historical validator, not unrelated CI repair.

[VER-004] Record raw commands, exit statuses, artifact hashes, field-level parity results, changed files, and any exclusions in a durable extraction checkpoint. A passing aggregate metric is insufficient when question/evidence/posterior/classification/stopping/deck/mask parity can be compared directly.

[PERF-001] No production runtime improvement is claimed. The new target may change build cost and validation-run overhead; measure those only if material. Product hot-path performance requires no new infrastructure unless parity or the existing benchmark reveals a concrete regression.

[PERF-002] The parallel private GUI timing matrix in `GATE-003` is development evidence only. On the frozen final code/model/configuration/resource tree, after the development-confirmation and release-holdout progression permits release assessment, rerun controlled Release benchmark repetitions and the representative private six-document PDF/EPUB/DOCX real-app matrix with document-open controls and “next question answerable” timing. Revalidate the 150 ms algorithm p95, 16 ms uninterrupted main-thread p95, and same-machine visible-ready control + max(10% of control, 50 ms) opening gates; retain every raw and adverse repetition. Any later relevant source/configuration change invalidates and requires repetition of affected final-tree evidence.

## Remaining scientific and release gates

[GATE-001] Gate 1 remains the immediate blocker: complete independent statistical, research, and privacy review. The reviewer must decide exactly these seven intentionally unset groups: the known-claim interference margin/method; the full categorical-response guardrail; criterion-K acquisition/classification/rater uncertainty/sensitivity; immutable product-version and evidence-mapping binding; repeat prompt/definition/distractor/delay and rare-denominator precision; one formal conditional tail-severity endpoint; and sample size/dependence/missingness/consent/retention/deletion/named approval.

[GATE-002] Gate 2 begins only after that approval and consists of two small developmental human studies, not the full validation study. First test whether the pretest changes the complete first-stage distribution over `I know it`, `Not sure`, and `I don't know`, while reporting `Not a word/name` separately without renormalization; both the known-claim endpoint and the approved categorical guardrail must pass. Second estimate persistence/dependence of erroneous `verifiedKnown` responses when the same item is confirmed again using the approved repeat-event protocol.

[GATE-003] Gate 3 may run in parallel with review and the architectural extraction: execute a developmental representative private PDF/EPUB/DOCX GUI timing matrix using “next question answerable,” not merely visible, and continue POS work only on fresh development material, prioritizing errors that change assessable lexical identity or occurrence mass. This early matrix cannot substitute for the frozen-final-tree rerun in `PERF-002`.

[GATE-004] Gate 4 uses the developmental human results to choose the warm path. If repeated wrong-known responses are highly correlated, abandon confirmation and investigate stopping/prior policies only when external evidence warrants it. If confirmation adds genuinely independent safety information at acceptable burden, design one final candidate from that evidence. If pretest interference is material, redesign criterion sampling/order for the main validation study before continuing.

[GATE-005] Gate 5 begins only after the active v3 reservation is sealed and disjoint from all prior development and release sets. It freezes exactly one candidate and binds its candidate commit and clean-tree hash, model/configuration/resource hashes, study rules, thresholds, analysis and decision-rule checksum, schemas, and source locks. Broad candidate searching stops at freeze.

[GATE-006] Gate 6 runs only the active v3 reservation exactly once, after the candidate and analysis are frozen, its generator binding is valid under `LOCK-002`–`LOCK-003` and `LOCK-007`, and a separate reviewed decision to consume that specific reservation is recorded. It requires the candidate commit and clean-tree hash, model/configuration/resource hashes, and analysis/decision-rule checksum before execution. The v1/v2 reservations remain unexecuted historical evidence and are never silently consumed or rebound. Failure returns the project to development, preserves the adverse evidence, and requires a future fresh confirmation reservation; the viewed set is never queried again as untouched confirmation.

[GATE-007] Gate 7 uses the final release holdout only after development-confirmation passes. Existing failed release evidence remains preserved, and the holdout is a last synthetic gate rather than a tuning dataset.

[GATE-008] Gate 8 then performs real-learner validation for the actual claims: calibration, important-unknown vocabulary capture, the 98% coverage interpretation, and warm-personalization non-inferiority.

[GATE-009] The structural extraction may proceed during the review quiet period. Human collection depends on the relevant study execution boundary being stable: the Core/Validation dependency direction finalized; relevant assessment and study schemas finalized; the study execution path parity-verified; current executable and product-version hashes frozen; and independent statistical/research/privacy review approved. Do not move a data-generating or interpreting path while that study is collecting. Unrelated POS or cross-format helper housekeeping need not finish before an otherwise approved human study; completing the entire extraction is not a new scientific gate. The extraction does not bypass, satisfy, or reorder Gates 1–8.

[GATE-010] CI repair may proceed independently, but CI status is not evidence for or authority over the scientific decisions above.

## Failure handling and stop conditions

[NEG-001] Do not invent safeguard #3; tune the warm weight; change the 512 production sample count; promote the remaining-unasked selector; change evidence reliabilities from synthetic failures; tune POS thresholds on the consumed held-out POS set; run development-confirmation “just to see”; reopen the release holdout; add elaborate governance layers; duplicate the production CAT; or use this extraction to alter model/study behavior.

[FAIL-001] On a parity, schema, RNG, dependency, or evidence-hash failure, stop the affected slice, discard its failed candidate changes, return to the locked pre-slice state, and reapply only the demonstrated repair. Do not patch goldens, schemas, reservations, or historical evidence to absorb the discrepancy.

[FAIL-002] If Validation appears necessary to the shipping App, first determine whether the concept is genuinely production behavior. Production facts may receive a narrow Core owner; experimental interpretation remains in Validation. Do not add a reverse dependency, untyped escape hatch, or forwarding API to make the build pass.

[FAIL-003] If a required baseline payload is missing, a source hash no longer matches outside the explicitly reviewed `LOCK-003` migration, or any sealed dataset is accessed, mark the extraction checkpoint incomplete and request direction. A historical Git object absent from a shallow checkout is an infrastructure failure, not evidence that the generator hash changed: repair the deterministic checkout/fetch and rerun the validator before interpreting the lock. If the locked object cannot be retrieved after that repair, stop as incomplete and request direction. Do not reconstruct exact contracts from memory or substitute a plausible fixture.

[FAIL-004] The earlier extraction checkpoint remains historically complete against the acceptance criteria in its accepted plan at that time; new `AC-008` is a post-extraction follow-up requirement and does not retroactively reopen or rewrite that checkpoint. This follow-up closes only when its amended acceptance criteria, register and all-prior identity checks, v2 historical-source verification, v3 seal, and verification gates pass and a separate durable checkpoint records the evidence. Neither historical nor follow-up completion approves the seven review decisions or permits confirmation/holdout data access.

## Deferred and superseded choices

[DEF-001] A `LeafReaderValidationCLI` SwiftPM target is deferred. Reconsider it only after the library extraction proves that stable script adapters still duplicate substantial command/bootstrap code; preserve command names, flags, exits, and artifact schemas in any later migration.

[DEF-002] A generic Support layer is deferred until at least a second experiment genuinely shares a primitive. Keep vocabulary code under the vocabulary namespace; do not disguise a single-use abstraction with generic type parameters.

[DEF-003] A separate package/repository remains deferred until there is a demonstrated need for independent versioning/lifecycle, multiple repositories, materially different dependencies, separate build/test invocation, or stronger source visibility than a target supplies.

[SUP-001] Superseded: the earlier broad recommendation for an immediately reusable validation library ecosystem is replaced by one repository-internal SwiftPM target with no product or versioning commitment.

[SUP-002] Superseded: the earlier five-commit sketch's immediate CLI target is replaced by stable thin script adapters now and the explicit deferred decision in `DEF-001`.

[SUP-003] Superseded: the earlier generic experiment-platform direction is replaced by vocabulary-specific code and the second-use-case rule in `DEF-002`.
