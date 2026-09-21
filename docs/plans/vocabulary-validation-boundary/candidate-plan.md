# LeafReader validation boundary and remaining-gates implementation plan

## Status and authority

[AUTH-001] This is a new candidate plan, not a preservation revision and not yet a canonical or accepted plan. No trustworthy prior plan for this extraction was identified. User acceptance may promote this candidate as the implementation base; until then, it authorizes no code changes, data collection, confirmation run, or holdout access.

[AUTH-002] The authoritative product and scientific contracts remain the hash-locked vocabulary roadmap, its target ledger, the current evidence-status register, the sealed reservations, and the review-readiness artifacts named in `source-lock.json`. This plan schedules and constrains a structural extraction; it does not amend those contracts.

[AUTH-003] The plan is prepared against clean repository revision `b2b99696feda177be0699d5277a2c13c7c7c9bd5`. If implementation starts from a different revision, re-run the ownership inventory and obtain a newly reviewed source lock, plan delta, and baseline before moving code. Once implementation begins, the recorded baseline lock is immutable; expected source edits receive separate current-candidate provenance.

## Decision and acceptance criteria

[GOAL-001] The goal is worthy: production code, correctness tests, model-validation experiments, and human-research evidence must have visibly different owners and dependency directions. The benefit sought is comprehensibility, containment of research concepts, safer evidence evolution, and reviewability of what ships; cross-feature reuse is optional.

[GOAL-002] The necessary architecture is a one-way boundary between shipping behavior and validation behavior. The current shared Swift machinery is substantial enough to justify one internal `LeafReaderValidation` target, but not a separate package, repository, public SDK, or framework ecosystem.

The extraction is accepted only when all of the following are true:

- [AC-001] LeafReader's shipping product still consists only of `LeafReaderApp` and `LeafReaderCore`, with unchanged user-visible behavior and production semantics.
- [AC-002] Validation executes the production assessment, vocabulary-index, coverage/deck, prior, and difficulty implementations; it does not copy their equations or policies.
- [AC-003] Experiment concepts are absent from App-facing and production-facing APIs except for a package-scoped, immutable Core observation surface that exposes production facts.
- [AC-004] Deterministic runner outputs and frozen-fixture decisions match the pre-extraction baseline under the parity rules below.
- [AC-005] Historical evidence remains immutable, existing reservations remain sealed, and no scientific or release gate is reordered.
- [AC-007] The sealed development-confirmation generator lock is either honored by the unchanged historical generator or superseded only through an explicitly reviewed, additive binding/reservation decision made before pinned source changes; the original manifest is never rewritten.
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

[ARCH-002] `LeafReaderValidation -> LeafReaderCore` is the only allowed production-code dependency involving the validation target. `LeafReaderCore` and `LeafReaderApp` must neither import nor declare a target dependency on `LeafReaderValidation`.

[ARCH-003] `LeafReaderValidation` is repository-internal infrastructure: no semantic-version promise, external product, public SDK design, or cross-repository lifecycle is introduced.

[ARCH-004] Use `Sources/LeafReaderValidation/Vocabulary/` for vocabulary-specific execution and evaluation code. A top-level `Validation/Vocabulary/CURRENT.md` may serve as a short, non-authoritative pointer to current hash-locked protocols and evidence; it must not duplicate or replace their normative payloads.

[ARCH-005] Preserve existing script entry paths and flags during the extraction. Scripts become thin composition/orchestration adapters around Core plus `LeafReaderValidation`; changing the CLI is a separate future decision.

## Ownership classification

[OWN-001] `LeafReaderCore` continues to own the single production implementation of `AdaptiveVocabularyAssessment`, its model configuration, knowledge and observation semantics, question selection, cross-moment scoring, coverage sampling, deck construction, stopping, `VocabularyReaderPrior`, difficulty behavior, and the document vocabulary inventory/index.

[OWN-002] Keep a package-scoped, immutable `VocabularyAssessmentDiagnosticSnapshot`-style carrier in Core because it describes observable production state. Narrow it to the facts required by current validation: frozen item identity and occurrence mass, inclusion/evidence, response curves, posterior and epsilon state, reliability scale, production selection, production masks/strata, and fingerprints. Give Validation read-only package access only to the facts its evaluator needs; do not expose a generic mutable/native escape hatch. Snapshot construction must not mutate caches, consume additional shared random-stream state, alter stopping, or change the next question.

[OWN-008] Split the current mixed `VocabularyDiagnosticInputError` alongside the snapshot split: Core may retain only errors required to construct or observe production facts, while bank-specific cases such as `incompatibleB1SampleCount` move with the A/B1/B2 evaluator to Validation. Preserve equivalent rejection behavior and test it on both sides of the boundary; do not make Core import a Validation error type.

[OWN-009] Remove the experimental `selectionOverride:` parameter from Core's `AdaptiveVocabularyAssessment.diagnosticSnapshot`. Its selection must always be the production-selected set. Counterfactual selected-set evaluation belongs in Validation against that immutable snapshot, using the existing evaluator's `selectedKeys:` concept or an equally narrow Validation-owned operation. Preserve current counterfactual outputs and reject unknown or excluded override keys as before.

[OWN-003] Move experimental interpretation out of Core: A/B1/B2 bank kinds and configuration, independent-bank generation/evaluation, fixed-bank controls, synthetic truth and responses, experiment arms, confirmation experiments, forensic cases, replay/counterfactual orchestration, longitudinal histories, validation manifests, experiment reports, and reservation-aware runner mechanics belong to `LeafReaderValidation`.

[OWN-004] Move `VocabularyValidationStudyDataset.swift`, `VocabularyValidationStudyPackageV2.swift`, and their validation-specific tests to the validation target. Their Codable shapes, validation rules, and serialized bytes remain unchanged.

[OWN-005] Keep `VocabularyPredictionAudit` and `VocabularyResearchExport` in Core for this extraction because the shipping App currently consumes them. Removing or redesigning those product flows would be a separate product decision and must not be smuggled into this refactor.

[OWN-006] Swift owns faithful execution of production behavior: assessment runs, synthetic answers, deck construction, prior-store histories, replay, diagnostics, and evidence capture. Python continues to own aggregation, statistical fitting, DIF/study analysis, report comparison, and schema validation. The first extraction does not relocate Python merely for directory symmetry.

[OWN-007] Correctness tests remain beside their implementation owners. Algebra parity, deterministic deck ordering, prior-store persistence, model arithmetic, and App coordination tests stay in Core/App test targets. Tests move to `LeafReaderValidationTests` only when the behavior under test moves to `LeafReaderValidation` or is explicitly an experiment-quality claim.

## Evidence preservation and parity

[EVID-001] Validation software is maintainable and refactorable; protocols, source locks, frozen reports, failed-candidate evidence, consumed holdouts, experiment checkpoints, reservations, approvals, and old protocol versions are immutable historical evidence.

[EVID-002] Do not move or rewrite the existing archive under `docs/plans/vocabulary-validation-evidence/` or the existing performance evidence under `docs/perf/`. New navigation may point to them by repository-relative path and SHA-256. Any future archive relocation requires a separate migration with link and checksum preservation.

[PAR-001] The extraction must not change seeds, RNG stream derivation or consumption, algorithms, equations, thresholds, evidence reliabilities, question ordering, stopping, experiment definitions, sample counts, report schemas, field names, encodings, command flags, reservation semantics, or checksums of historical evidence.

[PAR-002] Build the pre-extraction and post-extraction runners and execute both against the same authorized fixtures and manifests. Require byte-identical deterministic JSON/Markdown and identical exit status where source/path-independent. For fields whose contract is truthful source identity or wall-clock timing, retain both raw artifacts and compare all remaining fields after a predeclared canonicalization that removes only those fields; do not normalize metric values, seeds, identifiers, decisions, missingness, or failure records.

[PAR-003] Existing evaluator, causal, longitudinal, POS, and validator entry paths remain callable with the same arguments. Existing JSON remains decodable by current validators; frozen fixtures remain accepted or rejected exactly as before. Golden or schema updates cannot be used to make a parity failure pass.

[DATA-001] Baseline and parity scoring runs may use ordinary development fixtures and existing self-tests only. They must not score the sealed development-confirmation reservation, the release holdout, consumed POS held-out cases, or any human collection path. Existing deterministic validators may read the already-consumed POS fixture and report solely to verify historical integrity; this does not make those cases fresh development material or permit new predictions, tuning, or candidate comparisons on them.

## Sealed generator-lock compatibility checkpoint

[LOCK-001] `development-confirmation-reservation-v1.json` pins SHA-256 values for `scripts/evaluate_vocabulary_assessment.sh`, `scripts/evaluate_vocabulary_assessment.swift`, `scripts/vocabulary_assessment_causal_diagnostics.swift`, and the canonical gate ledger. Its current validator checks the files at those repository paths, and `scripts/check.sh` runs that validator. Moving the pinned Swift implementation or changing the shell wrapper therefore breaks the seal check even if evaluator outputs remain identical. Report parity alone cannot repair this source-identity mismatch.

[LOCK-002] Before editing any pinned generator file or removing Core declarations required by it, obtain an explicit reviewed decision on the reservation's future binding. The decision must say whether the still-uninspected seed/document set may be carried into a new additive binding for the extracted generator, or whether the original reservation must be retained as unexecuted historical evidence and a distinct fresh reservation created. Do not assume that an unchanged seed set can be silently rebound, and do not modify the original manifest to make its hashes match.

[LOCK-003] In either reviewed route, preserve the original manifest and verify its pinned generator bytes from the recorded Git revision so its existing self-test remains green after source movement. If additive rebinding is approved, separately lock the new generator's source paths, hashes, transitive Core/Validation build inputs, Swift 6 flags, and output/decision parity on ordinary development fixtures. If a distinct fresh reservation is required instead, create and freeze its current-generator binding before any outcome access while retaining the original as unexecuted historical evidence. The revised checks must fail unless the historical lock and the applicable current binding are valid, outcomes remain uninspected, and execution remains blocked pending candidate/analysis freeze and the reviewed consumption decision.

[LOCK-004] Until the reviewed route and its validator are green, the extraction may proceed only in nonconflicting slices. Do not edit the pinned runner, evaluator, or causal-support paths, nor remove Core APIs that the frozen runner needs. If this prevents the complete one-way boundary, stop and report a partial extraction rather than weakening `check.sh` or claiming completion.

[LOCK-005] The current evaluator and POS shell wrappers compile standalone Swift with `swiftc` and link only `libLeafReaderCore.a`; a new SwiftPM target is not automatically available to them. In the approved route, explicitly build/link `LeafReaderValidation` in the same package-access context, Swift 6 mode, optimization mode, and warnings-as-errors regime, or use an equivalent proven invocation. Preserve existing wrapper paths, flags, exit behavior, and deterministic artifacts; test a clean build with no cached modules.

[LOCK-006] This plan's `source-lock.json` is a historical baseline lock for the clean `b2b99696feda177be0699d5277a2c13c7c7c9bd5` source tree and the attached user brief. After extraction, verify repository entries against that recorded Git tree and the external brief against its locked attachment bytes, not against current edited repository paths; record a separate current-candidate source/build lock. Do not refresh the baseline lock to make changed files match. A changed starting tree before implementation requires a newly reviewed baseline and plan delta, while an expected implementation edit requires current-candidate provenance.

## Implementation sequence

[IMPL-001] Implement the extraction as the following five dependency-ordered, independently reviewable commits after a read-only baseline checkpoint and the `LOCK-002` decision. Do not combine the extraction with model experimentation. If that decision is pending, perform only nonconflicting preparation and do not enter the pinned-file slices.

### Baseline checkpoint — no source changes

1. Record the starting commit, dirty state, Swift version, package graph, relevant source hashes, CLI help/flags, and historical evidence hashes.
2. Build the existing evaluator/POS executables in an isolated build directory.
3. Capture authorized self-test and small development-fixture outputs, raw timing/provenance, exit statuses, and validators.
4. Record the exact normalization rule for unavoidable timing/source-identity differences before seeing post-extraction output.
5. Verify the sealed generator hashes at their current paths and record the reviewed `LOCK-002` decision before scheduling any pinned-file edit.

### Commit 1 — target scaffold and boundary

1. Add `LeafReaderValidation` and `LeafReaderValidationTests` to `Package.swift` without adding a product or App dependency.
2. Add the dependency-direction check and its negative fixtures first.
3. Add the short `Validation/Vocabulary/CURRENT.md` pointer without moving evidence.
4. Prove that a no-content target scaffold does not alter the app product or baseline runner behavior.
5. Prove an isolated Swift 6 build/link path for Validation code without changing the pinned runner wrapper before the binding decision is effective.

### Commit 2 — schemas and Core observation seam

1. Move the two validation-study schema/validator files and their tests to the validation target without changing their declarations or Codable contracts beyond the access control required by the in-package target boundary.
2. Split `VocabularyAssessmentCausalDiagnostics.swift`: retain only the immutable production-fact snapshot, its Core-only construction errors, and snapshot construction seam in Core; move fixed-bank and A/B1/B2 interpretation/evaluation plus bank-specific errors to Validation. Remove Core's `selectionOverride:` experiment knob and keep selected-set counterfactuals in Validation.
3. In the same commit, after the reviewed generator-binding route is effective, update the existing causal/longitudinal script imports and pinned evaluator wrapper to build and link Validation alongside Core. The moved evaluator must compile against read-only package-scoped snapshot facts; do not leave scripts depending on removed Core bank symbols between commits.
4. Keep `AdaptiveVocabularyAssessment` as the sole equation/policy implementation and prove snapshot observation, runner outputs, and the integrated evaluator self-test remain green at this commit boundary.

### Commit 3 — assessment, causal, and longitudinal runners

1. Move shared synthetic reader/truth/response, paired substream, replay, forensic, manifest, report, provenance, and metric mechanics from the large Swift scripts into `LeafReaderValidation/Vocabulary/`.
2. Keep evaluator command parsing and file I/O as thin adapters with unchanged flags and exit behavior.
3. Retain the Commit 2 wrapper/import/link integration while moving runner internals; verify a clean build without relying on an old cached Core or Validation module.
4. Compare old and new outputs on every locked baseline case before deleting duplicate script-local code.

### Commit 4 — POS and cross-format validation helpers

1. Move reusable Swift POS evaluation and cross-format validation execution helpers into the validation target.
2. Keep production lexical identity, occurrence accounting, vocabulary inventory, parsing, and objective implementations in Core.
3. Keep Python statistical/reporting validators in their current role and use only fresh development POS material for new scoring or tuning; allow the existing read-only historical-integrity validator, but do not produce new predictions or candidate comparisons on the consumed held-out POS set.

### Commit 5 — enforcement, documentation, and stop

1. Wire the dependency-direction check and validation tests into `scripts/check.sh`.
2. Verify existing script compatibility, evidence paths, the immutable historical baseline lock against recorded Git blobs, the approved current-generator binding, and deterministic report parity.
3. Update the concise architecture document and `CURRENT.md` only with the boundary that was actually implemented.
4. Run the full verification matrix below, publish the extraction checkpoint, and stop. Do not redesign the assessment, introduce a new safeguard, or start the deferred generalization/CLI work.

## Verification

[VER-001] Narrow tests must cover: Core snapshot immutability, production-selection identity, Core-only construction errors, and next-question parity; Validation-only selected-set counterfactual parity including unknown/excluded-key rejection; production-A parity; B1 strata, latent-stream behavior, and bank-specific error rejection; B2 independent theta/latent behavior; fixed-bank and mass-conservation controls; validation-study schema round trips and privacy rejections; causal/longitudinal/POS self-tests; and unchanged App coordination for the Core-owned prediction-audit/research-export flows.

[VER-002] The architecture check must parse the SwiftPM target graph and inspect source imports. It fails if Core or App depends on/imports Validation, if the `LeafReaderApp` product reaches Validation transitively, or if validation-only names such as synthetic truth, holdout, experiment arm, forensic failure, A/B1/B2, or confirmation candidate appear in production public/package APIs outside the approved snapshot carrier.

[VER-003] Run, at minimum, the affected strict Swift tests while iterating, then `swift build -Xswiftc -warnings-as-errors`, `swift test -Xswiftc -warnings-as-errors`, `./scripts/check.sh --no-build`, and `./scripts/build_app.sh`. Package/app assembly is in scope because `Package.swift` changes even though UI behavior does not.

[VER-004] Record raw commands, exit statuses, artifact hashes, field-level parity results, changed files, and any exclusions in a durable extraction checkpoint. A passing aggregate metric is insufficient when question/evidence/posterior/classification/stopping/deck/mask parity can be compared directly.

[PERF-001] No production runtime improvement is claimed. The new target may change build cost and validation-run overhead; measure those only if material. Product hot-path performance requires no new infrastructure unless parity or the existing benchmark reveals a concrete regression.

[PERF-002] The parallel private GUI timing matrix in `GATE-003` is development evidence only. On the frozen final code/model/configuration/resource tree, after the development-confirmation and release-holdout progression permits release assessment, rerun controlled Release benchmark repetitions and the representative private six-document PDF/EPUB/DOCX real-app matrix with document-open controls and “next question answerable” timing. Revalidate the 150 ms algorithm p95, 16 ms uninterrupted main-thread p95, and same-machine visible-ready control + max(10% of control, 50 ms) opening gates; retain every raw and adverse repetition. Any later relevant source/configuration change invalidates and requires repetition of affected final-tree evidence.

## Remaining scientific and release gates

[GATE-001] Gate 1 remains the immediate blocker: complete independent statistical, research, and privacy review. The reviewer must decide exactly these seven intentionally unset groups: the known-claim interference margin/method; the full categorical-response guardrail; criterion-K acquisition/classification/rater uncertainty/sensitivity; immutable product-version and evidence-mapping binding; repeat prompt/definition/distractor/delay and rare-denominator precision; one formal conditional tail-severity endpoint; and sample size/dependence/missingness/consent/retention/deletion/named approval.

[GATE-002] Gate 2 begins only after that approval and consists of two small developmental human studies, not the full validation study. First test whether the pretest changes the complete first-stage distribution over `I know it`, `Not sure`, and `I don't know`, while reporting `Not a word/name` separately without renormalization; both the known-claim endpoint and the approved categorical guardrail must pass. Second estimate persistence/dependence of erroneous `verifiedKnown` responses when the same item is confirmed again using the approved repeat-event protocol.

[GATE-003] Gate 3 may run in parallel with review and the architectural extraction: execute a developmental representative private PDF/EPUB/DOCX GUI timing matrix using “next question answerable,” not merely visible, and continue POS work only on fresh development material, prioritizing errors that change assessable lexical identity or occurrence mass. This early matrix cannot substitute for the frozen-final-tree rerun in `PERF-002`.

[GATE-004] Gate 4 uses the developmental human results to choose the warm path. If repeated wrong-known responses are highly correlated, abandon confirmation and investigate stopping/prior policies only when external evidence warrants it. If confirmation adds genuinely independent safety information at acceptable burden, design one final candidate from that evidence. If pretest interference is material, redesign criterion sampling/order for the main validation study before continuing.

[GATE-005] Gate 5 freezes exactly one candidate and binds its candidate commit and clean-tree hash, model/configuration/resource hashes, study rules, thresholds, analysis and decision-rule checksum, schemas, and source locks. Broad candidate searching stops at freeze.

[GATE-006] Gate 6 runs the reviewed active sealed development-confirmation reservation exactly once and only after the candidate and analysis are frozen, its generator binding is valid under `LOCK-002`–`LOCK-003`, and a separate reviewed decision to consume that reservation is recorded. The active reservation must require the candidate commit and clean-tree hash, model/configuration/resource hashes, and analysis/decision-rule checksum before execution. If the fresh-reservation route is chosen, the original remains unexecuted historical evidence and is not silently consumed. Failure returns the project to development, preserves the adverse evidence, and requires a future fresh confirmation reservation; the viewed set is never queried again as untouched confirmation.

[GATE-007] Gate 7 uses the final release holdout only after development-confirmation passes. Existing failed release evidence remains preserved, and the holdout is a last synthetic gate rather than a tuning dataset.

[GATE-008] Gate 8 then performs real-learner validation for the actual claims: calibration, important-unknown vocabulary capture, the 98% coverage interpretation, and warm-personalization non-inferiority.

[GATE-009] The structural extraction may proceed during the review quiet period, but it must finish and publish parity evidence before any human study or frozen candidate binds new executable paths. It does not bypass, satisfy, or reorder Gates 1–8.

[GATE-010] CI repair may proceed independently, but CI status is not evidence for or authority over the scientific decisions above.

## Failure handling and stop conditions

[NEG-001] Do not invent safeguard #3; tune the warm weight; change the 512 production sample count; promote the remaining-unasked selector; change evidence reliabilities from synthetic failures; tune POS thresholds on the consumed held-out POS set; run development-confirmation “just to see”; reopen the release holdout; add elaborate governance layers; duplicate the production CAT; or use this extraction to alter model/study behavior.

[FAIL-001] On a parity, schema, RNG, dependency, or evidence-hash failure, stop the affected slice, discard its failed candidate changes, return to the locked pre-slice state, and reapply only the demonstrated repair. Do not patch goldens, schemas, reservations, or historical evidence to absorb the discrepancy.

[FAIL-002] If Validation appears necessary to the shipping App, first determine whether the concept is genuinely production behavior. Production facts may receive a narrow Core owner; experimental interpretation remains in Validation. Do not add a reverse dependency, untyped escape hatch, or forwarding API to make the build pass.

[FAIL-003] If a required baseline payload is missing, a source hash no longer matches outside the explicitly reviewed `LOCK-003` migration, or any sealed dataset is accessed, mark the extraction checkpoint incomplete and request direction. Do not reconstruct exact contracts from memory or substitute a plausible fixture.

[FAIL-004] The extraction is complete only when all acceptance criteria and verification gates pass and a durable checkpoint records the evidence. Completion of the extraction says nothing about approval of the seven review decisions or readiness to run confirmation/holdout data.

## Deferred and superseded choices

[DEF-001] A `LeafReaderValidationCLI` SwiftPM target is deferred. Reconsider it only after the library extraction proves that stable script adapters still duplicate substantial command/bootstrap code; preserve command names, flags, exits, and artifact schemas in any later migration.

[DEF-002] A generic Support layer is deferred until at least a second experiment genuinely shares a primitive. Keep vocabulary code under the vocabulary namespace; do not disguise a single-use abstraction with generic type parameters.

[DEF-003] A separate package/repository remains deferred until there is a demonstrated need for independent versioning/lifecycle, multiple repositories, materially different dependencies, separate build/test invocation, or stronger source visibility than a target supplies.

[SUP-001] Superseded: the earlier broad recommendation for an immediately reusable validation library ecosystem is replaced by one repository-internal SwiftPM target with no product or versioning commitment.

[SUP-002] Superseded: the earlier five-commit sketch's immediate CLI target is replaced by stable thin script adapters now and the explicit deferred decision in `DEF-001`.

[SUP-003] Superseded: the earlier generic experiment-platform direction is replaced by vocabulary-specific code and the second-use-case rule in `DEF-002`.
