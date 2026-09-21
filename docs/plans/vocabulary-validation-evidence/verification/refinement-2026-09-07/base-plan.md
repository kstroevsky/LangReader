# Vocabulary validation and release-evidence implementation plan

## Authority and scope

Prepared on 2026-09-07 against source revision `e8ea803c2a9eb557677a520f4c97aacf729e7c52`.

This is an additive implementation plan for the reviewed validation improvements. It is not a replacement canonical roadmap, a release approval, an approved SAP, or permission to collect confirmatory data. The current task creates documentation only.

The authoritative [candidate roadmap](../vocabulary-measurement-coherence-authorized/candidate-roadmap.md) has SHA-256 `b218edcb4deff49af2e899553e196d562aa2de0e1a004e49b81bee134ba67512`. Its [acceptance](../vocabulary-measurement-coherence-authorized/acceptance-2026-08-25.md) and [target ledger](../vocabulary-measurement-coherence-authorized/target-ledger.json) continue to govern all 42 active and 12 deferred requirements. Active means authoritative, not unfinished. All unmentioned requirements remain unchanged.

The plan records the user's preferred study amendments as concrete proposals. It does not silently amend the accepted source. Implement ordinary diagnostic work within its authorized scope; record the explicit amendment decisions identified below before applying changed canonical study requirements. Routine reversible work does not acquire an additional approval requirement from this document.

Supporting files in `verification/` record the initial scope scaffold, the execution requirement ledger, the feedback delta, and verification evidence. Their execution IDs are local tracking identifiers, not additions to the canonical 42/12 counts. Repository-relative paths below are resolved from the repository root unless they are Markdown links.
## Evidence baseline

<!-- requirement: EVIDENCE -->

The objective is to explain coverage failures, test the real personalization feedback loop, and make human validation executable. This phase does not start from a finding that the production CAT is fatally flawed. Improving experimental identification takes precedence over more parameter tuning or a cleaner-looking selector.

| Evidence | Established result at the inspected revision | Limit of the conclusion |
| --- | --- | --- |
| Optimized 10,000-lemma Release benchmark | Latest retained production p95: 13.66 ms cold all-unknown, 19.64 ms cold coverage, 22.40 ms warm coverage | Historical microbenchmark evidence; does not certify the eventual final tree, main-thread work, or usable UI latency |
| Paired selector experiments | Remaining-unasked loss loses 2.6 percentage points of idiosyncratic coverage; combined latent-state variant loses about 4.7 points versus production | Grounds for retaining production under the synthetic guardrail, not proof of superior human validity |
| Frozen version-3 holdout | One of three seeds passes all gates; response-noise hit rate reaches 87.5%, idiosyncratic hit rate 84.375%, warm coverage degradation 4.6875 points | Still adverse release evidence; aggregate calibration is not a deck-level guarantee |
| Diagnostic matrix | Two development seeds, eight readers per scenario per seed, 120 lemmas, four documents | A hit changes the per-seed rate by 12.5 points; detects large sensitivity, not a precise two-point effect |
| Human study | Protocol, SAP template, criterion-side schema and validator exist | No completed learner calibration or confirmatory coverage evidence |

Read [question-objective results](../../perf/vocabulary-question-objective-experiment-2026-09-07.md), [exact optimization](../../perf/vocabulary-assessment-optimization-2026-08-31.md), [holdout](../../perf/vocabulary-assessment-holdout-v1.md), [diagnostic matrix](../../perf/vocabulary-assessment-diagnostic-matrix-v1.json), [testing guide](../../perf/vocabulary-preparation-testing/README.md), [pilot](../../research/VOCABULARY_VALIDATION_PILOT.md), and [SAP template](../../research/VOCABULARY_VALIDATION_SAP_TEMPLATE.md). These are evidence/readiness sources, not permission to reinterpret the canonical gates.

Source checks found that `AdaptiveVocabularyAssessment.result()` uses the predictive samples for deck construction and reporting; `warmStartDiagnostics` injects a narrow true-theta-centered prior; `VocabularyReaderPriorStore.recordCompletedSession` stores the supplied completed posterior and increments counts; `lemmaSummaries()` reconciles some unknown-POS occurrences into a single confident class. These concrete seams guide the work below.

## Preserved production and release contracts

<!-- requirement: INVARIANTS -->

The complete unchanged contract is the hash-locked canonical roadmap linked above. The following operational guardrails are repeated to prevent accidental changes during diagnostic implementation:

- Preserve the one-dimensional Rasch-like model, version-3 migration, 121-point theta grid, nine-point difficulty quadrature, 512 production predictive samples, fifth-percentile coverage bound, 98% default target, 16-item shortlist, and production `allNonExcluded + evidenceSurrogate` selection. Exact cross-moment arithmetic and retained scheduling optimizations stay enabled; approximate 128-sample staged stopping stays diagnostic-only.
- Preserve evidence reliabilities: verifiedKnown 0.97, typedVerifiedKnown 0.98, verifiedUnknownOrPartial 0.98 toward unknown, reportedUnknown 0.95 toward unknown, unsure 0.75 toward unknown, legacyKnown 0.75, legacyUnknown 0.85; excluded supplies no ability evidence. The likelihood remains Core-owned. Epsilon knowledge and evidence reliability remain separate; tail contradictions update only epsilon knowledge, with Beta(1,19) smoothing and the 0.05–0.25 clamp.
- Preserve soft answered-item probabilities, estimated-known threshold 0.85, estimated-unknown threshold 0.15, all intervening uncertainty, exclusions, manual selection, saved Vocabulary Records and wildcard migration. Keep answer-before-reveal, known verification, unknown/unsure accounting, definition failure/retry/skip, and optional typed self-verification semantics.
- Preserve cold minimum 20, warm minimum 8, maximum 80; the warm minimum is conditional, not a promise to stop at eight. Preserve two completed sessions, 40 verified answers, freshness within 180 days, compatible language/version, two current tail validations, smoothing sigma 0.35 and the 90%/10% prior mixture. Preserve ordinary tail cadence and current warm-specific validation behavior by reusing production policy, not reproducing it in the simulator.
- Selected learning items count as mastered only in projected coverage. Creating a card is not evidence of mastery, and lexical coverage is not comprehension. Large-deck minimality is local, not global.
- Preserve privacy: no automatic uploads or response telemetry; normal research exports omit document identity/title/path, context, definitions, typed meanings, exact timestamps and account identity. Synthetic truth traces stay synthetic. Consented study data and local aggregate performance measurements have separate purposes and schemas.
- Preserve Core/App ownership, a single authoritative state owner, PDFKit/WebKit reader seams, Swift 6 and warnings-as-errors, asynchronous generation/request/cancellation guards, and existing persistence paths. Do not expand native-access allowlists or add controller forwarding surfaces for this work.

| Gate | Unchanged requirement |
| --- | --- |
| Well-specified calibration | ECE ≤ 0.05; 90% theta-interval coverage between 85% and 95% |
| Coverage hit | Well-specified and item-residual ≥ 95%; response-noise ≥ 90%; idiosyncratic ≥ 85% |
| Deck burden/precision | Precision ≥ 0.50 in every synthetic scenario/mode |
| Regression | No scenario/mode Brier or ECE degradation > 0.01 against the reviewed baseline; retain the report validator's coverage-hit regression guard of two percentage points |
| Warm benefit | Mean question reduction ≥ 25%; coverage-hit degradation no greater than two percentage points |
| Algorithm latency | 10,000-lemma answer-to-next-card p95 ≤ 150 ms; retain cold and warm reporting and all repetitions |
| Real-app work | Main-thread uninterrupted-work p95 ≤ 16 ms |
| Document opening | Same-machine visible-ready control + max(10% of control, 50 ms), for each required format |

The frozen three-seed/eight-document version-3 holdout and version-2 golden remain unchanged. New diagnostic success cannot waive a failed existing gate. Calibration slots remain disabled pending their separate approval. PR #9's description refresh is complete according to the user and is not reopened as unfinished work.

All twelve deferred ledger entries retain their original conditions: `SENSE-001`, `DOMAIN-003`, `DOMAIN-GATE-001`, `ASSUMP-005`, `PRIOR-004`, `DIFF-002`, `DOMAIN-004`, `L1DIFF-001`, `COVUX-002`, `COLD-001`, `MWU-001`, and `RISK-001`. They cover gated sense splitting, domain behavior and gates, empirical-model activation, empirical time diffusion, hierarchical difficulty, residual domain/L1 effects, alternative coverage targets, cold burden modes, multi-word units, and empirical risk control. Simulating these stressors or measuring burden does not enable them in production. Multi-word units still precede production same-POS sense splitting; 2PL and empirical packs retain their separate gates.

## Failed-deck forensic diagnostics

<!-- requirement: DIAG-TRACE -->

**Outcome:** every development coverage miss can be reconstructed and its missing occurrence mass accounted for, without reading private product data or guessing from aggregate ECE.

Extend `scripts/evaluate_vocabulary_assessment.swift` and its existing runners with an explicitly selected diagnostic output path. Keep the frozen release evaluator's default configuration, random consumption, report compatibility and selection behavior unchanged. Use a separate versioned diagnostic artifact where richer fields would otherwise alter frozen golden output. Concrete schema/CLI versions must be assigned and documented at implementation; names in this plan are conceptual, not an already-approved export schema.

Record a compact row for every reader-document-scenario run, not only failures. Retain detailed item rows for failures and a predeclared comparison sample of successes, or all runs if practical. Selection of detailed success rows must be independent of favorable metric movement.

| Record | Required information |
| --- | --- |
| Run identity | Synthetic reader/document IDs; language; scenario/history profile; source commit and dirty state; model/observation/resource versions; seed derivation and stream identities; inventory and truth fingerprints |
| Final assessment | True theta; estimated theta/interval; prior eligibility/use; question count; stop reason; final posterior fingerprint; exclusions; frozen proposed deck; manual override absent or separately identified |
| Coverage | Total assessable occurrence denominator; excluded/rejected mass separately; realized pre-learning coverage; realized projected coverage assuming selected items mastered; production expected coverage and lower bound; independent-bank results; shortfall from 0.98 |
| Missed unknown item | Lexical identity; occurrence count; final P(known); classification; answered/unasked/skipped status; evidence category and ordinal if answered; difficulty prior mean/SD/source/version; actual synthetic difficulty and residual; idiosyncratic flip provenance; selected status |
| Learning/response provenance | Latent knowledge before response; actual generated response; response-error draw/mechanism; any simulated learning or drift event, separately from evidence |

For assessable item j, let w_j be occurrence count, K_j hidden knowledge, and D the frozen selected set:

```text
W = sum_j w_j
missedMass = sum_j w_j * 1[K_j = 0 and j not in D]
realizedProjectedCoverage = 1 - missedMass / W
targetShortfall = max(0, 0.98 - realizedProjectedCoverage)
```

Record the empty-denominator convention explicitly and mark such runs ineligible for substantive hit-rate claims. Match production exclusion semantics; do not silently improve coverage by dropping difficult or unscorable items.

Create additive decompositions whose groups sum exactly to missedMass: answered versus unasked, and answered-by-evidence-category. Treat idiosyncratic flips, noisy responses and item residuals as overlapping mechanism flags unless a mutually exclusive attribution rule is declared before execution. Do not present overlapping percentages as an additive explanation. Report concentration in the largest missed items and the fraction of total document occurrences affected. The user's illustrative 61%/31%/8% breakdown is an example, not a measured target.

**Acceptance:** a fixture with known missed items reproduces hand-calculated mass and shortfall; zero-miss, excluded-item, high-frequency error, noisy-known answer, skipped-definition and empty-population cases are covered; detailed records join to aggregate counts; all failed and null runs remain available. Output size and diagnostics overhead are measured separately from production latency.

## Independent predictive evaluation banks

<!-- requirement: DIAG-BANK -->

**Outcome:** distinguish finite-bank selection optimism from ordinary Monte Carlo variation and from predictive-model failure.

Bank A remains the exact production 512-world bank used to construct the deck. Freeze the assessment posterior, epsilon, evidence, inventory, denominator and selected set before evaluating Bank B. B must never affect selection, stopping, posterior updates, the reported production result or subsequent answers.

Implement a narrow, immutable Core diagnostic sampling/evaluation seam near the existing `predictiveCoverageSamples` owner. Share the existing knowledge and observation semantics instead of independently rewriting the likelihood in Python. Parameterize independent seed material and evaluation sample count only for the explicit diagnostic call. Preserve existing production draws and mask ordering exactly. A copied assessment or immutable snapshot must not mutate production caches; do not call `result()` through a path that silently rebuilds a different deck.

Use independently derived deterministic streams for every evaluation replicate. The user's suggested 4,096 or 16,384 worlds are candidate diagnostic sizes, not new production defaults. Freeze sample count, replicate count, seeds and precision/convergence criteria in the development run manifest before inspecting outcomes. A seed change must affect all stochastic dimensions present in the sampler; deterministic theta stratification must be described honestly rather than claiming every bank component is randomized. Repeated copies of A or its masks are not independent banks.

For fixed D report Q0.05(A), Q0.05(B) for each replicate, their difference, estimated probability of coverage below 0.98 under B, and numerical variability. Evaluate successes as well as misses to avoid conditioning the diagnosis on failure alone. Include decks fixed independently of A and small analytically tractable cases as controls. Separate posterior-model uncertainty, finite-bank evaluation uncertainty and variation across synthetic learners/documents.

| Pattern across repeated runs | Permitted interpretation and next action |
| --- | --- |
| A systematically more optimistic than independent B beyond evaluation variability, especially for A-selected decks | Evidence consistent with selection optimism; compare fixed-deck controls and sample-size convergence before proposing a remedy |
| A and B agree but truth fails excessively across readers/documents | Evidence consistent with model miscalibration/misspecification; inspect evidence and missed-item decompositions |
| One truth realization misses despite agreeing banks | Not sufficient to diagnose misspecification; probabilistic bounds allow misses |
| A/B difference varies around zero or changes under repeated B seeds | Sampling variability or inconclusive evidence; retain uncertainty and increase diagnostic precision under the declared rule |
| More questions improve both banks and realized coverage | Investigate stopping; question selection and prior effects still require the controlled comparisons below |

**Acceptance:** same diagnostic manifest produces identical artifacts; B changes when its seed changes; production state and outputs are unchanged with diagnostics enabled/disabled; a fixed-deck control detects a deliberately biased evaluation fixture; small enumeration verifies the coverage denominator and quantile convention. B is never used to select a production parameter or to replace the frozen holdout. Testing larger banks does not activate an empirical risk-control layer.

## Stopping and posterior counterfactuals

<!-- requirement: DIAG-BUDGET -->

**Outcome:** distinguish loss from early stopping, posterior/prior effects and changed question paths without changing production's stopping contract.

- Run the natural production assessment first and save its complete path and natural stopping result.
- In a separate development-only continuation, use the same learner, document and potential response table to reach a predeclared question budget, bounded by the current 80-question ceiling and available eligible items. Record every natural stop that is deliberately bypassed. Exclusion, already-answered and exhaustion constraints still apply; never fabricate duplicate answers to reach a budget.
- Compare cold/warm at their natural stops, at a common feasible budget, and at shared checkpoints. Record unreachable budgets and reasons instead of silently dropping those runs. Do not assume fixed-budget coverage improves monotonically; preserve adverse results.
- Add common-question/common-evidence replay for both priors. Predeclare replay sequences from the natural cold path and natural warm path, and report both rather than choosing the favorable direction. Hold the evidence category, question order and validation-update treatment fixed for a controlled replay; separately retain natural validation-policy differences as part of the product comparison.
- If the production record API cannot replay the needed semantics, introduce a narrow diagnostic facility with tests for posterior replay and validation metadata. Never weaken `isFinished` or the production question-limit check globally. Label replay as a counterfactual, not an authentic reader-serving session.

A warm deficit disappearing at a common budget is consistent with a stopping contribution. Persistence at the common budget is not conclusive evidence against the prior alone: selection paths differ. A difference under common questions/evidence helps isolate posterior effects, conditional on that replay. If neither improves at the ceiling, report a limitation under the tested model/population, not proof that no possible intervention could help.

**Acceptance:** natural-mode paths remain identical; bypassed stops are explicit; fixed-budget and common-replay reports cannot enter release acceptance automatically; same inputs produce the same replay posterior; exclusions/exhaustion and validation contradictions are tested.

## Diagnostic reproducibility and attribution

<!-- requirement: DIAG-PAIR -->

Extend the existing paired-substream development mode rather than changing the frozen sequential release stream. Pre-generate or deterministically address latent truth and potential responses by learner, document/session, lexical item and response occasion. Drawing noise only by question ordinal makes a changed selector assign different noise to the same item; account for this when interpreting older paired reports. Freeze the intended common-random-number coupling and verify fingerprints for both truth and the response table, not truth alone.

Keep streams for document construction, item residuals, learner knowledge, response error, history/drift, predictive A, evaluation B, and diagnostic success sampling separate. Serial and supported parallel runs must agree; isolate temporary stores and outputs. Do not modify a learner's hidden state merely because one variant asked a different number of questions unless a separately declared learning scenario explicitly models that effect.

Choose the development reader/document counts from a precision/runtime plan and report raw counts beside percentages. Do not reuse eight-reader hit rates to support a two-point conclusion. Model participant/document clustering and paired comparisons when reporting uncertainty; estimator and interval choices for these synthetic diagnostics must be documented before the run, without preempting the separate human SAP. Freeze materiality/decision rules before outcomes; leave an inconclusive outcome available. Existing one-factor reliability, epsilon, difficulty-SD, quantile and warm-weight probes remain retained sensitivity evidence, not a production parameter search leaderboard.

Produce one machine-readable report plus a concise mechanism report for every planned run. Record failed/null experiments, exceptions, interrupted runs, environment, source and build settings, configurations and hashes. Add deliberately inconsistent fingerprints, broken denominators, biased-bank cases and duplicate IDs as negative controls. Independent hand calculations or enumerated fixtures must check the shared implementation; matching two calls to the same helper is not an independent oracle.

## Longitudinal warm-start simulation

<!-- requirement: WARM-HISTORY -->

**Outcome:** test the actual completed-assessment-to-local-prior feedback loop rather than injecting knowledge of the learner's true theta.

Use the existing evaluator/Core module build path and `VocabularyReaderPriorStore(databaseURL:)` with a disposable database per simulated learner/variant. Never use `.shared` or the user's `personal-vocabulary.sqlite3`. Advance a fixed synthetic clock so freshness and repeated runs are deterministic.

For history documents A/B/C and evaluation document D (illustrative labels, not a fixed mandatory history length):

1. Generate a coherent learner and document series, retaining lexical overlap, fixed item effects and learner-item exceptions where the scenario calls for them.
2. Load the language prior from the isolated production store. Apply production eligibility/version logic and construct the real assessment.
3. Run the answer-before-reveal evidence protocol with the declared response noise. Hidden truth and true theta are available only to the generator and scoring oracle.
4. At actual completion, pass `thetaPosteriorSnapshot`, `verifiedEvidenceCount`, completion time, language, algorithm version and a unique contribution ID through `recordCompletedSession`, matching `VocabularyPreparationCoordinator.recordReaderPriorContributionIfNeeded`.
5. Reload the store, checking posterior, counts, timestamp and eligibility. The current store replaces its posterior with the supplied completed posterior and increments counters; it does not independently multiply session posteriors. Do not invent a second accumulation formula. Earlier history influences later results through the production warm-start path when eligible.
6. On D, fork the same hidden learner/document into cold and accumulated-warm evaluations; do not let one variant's completion contaminate the other's store. Apply the natural, matched-budget and common-replay comparisons.

Core integration tests verify SQLite round trips and idempotency. App coordinator tests verify the completion/contribution contract, including delayed save, stale request and retry behavior. The simulator itself should not import AppKit or invoke the full app to reproduce a Core persistence rule. Test failed writes and reopen/retry behavior in fixtures; never count an unsuccessful contribution as accepted history.

**Acceptance:** eligibility follows real counts and dates, not manually set flags; reloading reproduces the next assessment; duplicate completion does not double-count; incomplete/abandoned work does not become completed evidence; reset is language-scoped; passive exposure never contributes. Both eligible and ineligible history outcomes appear in reports instead of selecting only successful warm histories.

## Warm-history scenarios and comparisons

<!-- requirement: WARM-STRESS -->

Retain the current true-theta-centered, error-free-response diagnostic as an **oracle-informed reference**, not a mathematical upper bound and not a realistic history simulation. Give it a distinct label in reports.

Predeclare development histories covering stable knowledge, noisy answers, directionally biased self-verification, histories dominated by easy documents, histories dominated by hard documents, changed domain/difficulty distributions, reader ability drift, and repeated lexical items versus little overlap. Preserve learner-item exceptions across repeated items in stable scenarios; do not redraw an entirely different person on each document. Treat actual learning, fatigue, correlated response errors and drift as explicitly parameterized stressors, not as fitted human effects.

Exercise insufficient history, low verified counts, freshness boundaries, future timestamps, incompatible language/version, reset, duplicate contributions and cancelled sessions. Never forge eligibility to complete the longitudinal matrix. Select scenario strengths and history lengths in a versioned development manifest before outcomes, and report support for every cell; this plan does not invent empirical drift or noise estimates.

Report paired question reduction, coverage-hit difference, Brier/ECE, deck precision/burden, missed occurrence mass, posterior displacement/width, independent-bank discrepancy, stop reason, eligibility and question-path overlap. Keep all existing release gates separate and unchanged. History stress evidence can motivate a later authorized change but cannot enable production diffusion, L1 conditioning, domain blending or automatic prior suppression.

## Study sampling and sequence amendment

<!-- requirement: STUDY-SAMPLE -->

**Current contradiction:** the canonical large-document audit requires all selected cards plus sampled unselected items, while the protocol audits before the deck is known. Definitions revealed during assessment prevent post-hoc recovery of uncontaminated pre-reading labels.

**Preferred amendment to prepare:** for large documents, predetermine the independent criterion sample before assessment using known inclusion probabilities over the eligible lexical population. Estimate selected-card outcomes from selected items that happen to fall in that audit. Keep complete pretesting for small-document inventories. This replaces, rather than pretends to satisfy, the large-document requirement that every selected card have a pre-reading criterion. Record the exact `STUDY-002` roadmap/ledger/protocol delta before adopting it as the canonical confirmatory design.

Proposed sequence after the amendment decision:

1. Record separate study consent and preassign participant/document split membership; freeze inventory, model, domain metadata and pre-assessment strata.
2. Define the audit frame, stratum membership, sampling procedure, random seed and each item's inclusion probability before assessment responses or deck selection. Use frequency/predicted difficulty, POS and occurrence information, and baseline predicted-probability tails available at that time. Require positive inclusion probability for every item in the target estimand, or explicitly limit that estimand before collection.
3. Collect independent typed criterion responses for the fixed audit, with no definition/context or probability/deck disclosure and no feedback on correctness. Seal the responses for independent scoring; labels never enter assessment inputs.
4. Run the production assessment. Freeze final predictions for the full inventory, natural proposed deck and subsequent user-edited deck separately. Mark audited items as selected/unselected, asked/unasked and their final probability region afterward.
5. Conduct the standardized learning phase and immediate/delayed retests under the approved design. Additional post-learning selected-card tests may measure mastery, but must not be relabeled as pre-reading criterion observations.
6. Analyze the predetermined sample using the approved SAP and recorded inclusion probabilities. Report realized sample support in selected items and final probability tails; do not retrospectively top up pre-reading labels after reveal to improve support.

Pre-assessment strata cannot guarantee support in every final adaptive tail. Address expected support by design rehearsal and precision planning, not by claiming that future strata were known. The small-document census can supply direct selected-card labels, but a census remains subject to criterion ambiguity and participant effects.

Explicitly study **pretest interference** in consenting developmental work: prior retrieval attempts can change later self-verification, fatigue or learning even if labels remain hidden. Predeclare a feasible comparison/order design, record exposure and timing, and keep its data separate from confirmation. The amendment removes sampling circularity; it does not prove noninterference.

**Acceptance:** sampling can be executed before the first assessment response; no criterion row acquires a pre-reading label after reveal; original frame/probabilities are immutable and auditable; sparse/empty selected-audit strata are reported; inclusion probabilities, nonresponse and ambiguous criteria are distinct concepts; all sampling/retest stages needed by the chosen estimator are recorded.

## Meaning criterion and rater workflow

<!-- requirement: STUDY-RUBRIC -->

Prepare and rehearse the prompt: **“Write the meanings/translations you know for this word.”** The participant sees lemma + POS and no document context. Do not reveal a target sense or use production self-verification as independent ground truth.

The two trained bilingual raters may access the hidden document-relevant sense/context in a restricted, consented scoring workspace, while remaining blind to model probabilities, deck decisions, warm/cold condition and each other's initial scores. Raw context and typed responses must not leak into the ordinary product export or public analysis package. Freeze the target-sense mapping before observing answers or model outcomes where feasible.

The proposed criterion is known when independently produced meanings include the document-required sense. The rubric must define valid alternative translations, multiple senses, partial meanings, spelling/inflection tolerance, language proficiency effects on expression, and genuinely unscorable prompts. A correct alternative sense alone is not proof the learner lacks the target sense; record the limitation as a recall criterion. Multiple incompatible same-POS senses within a document require a frozen item-level scoring/occurrence rule or an ambiguity disposition, not post-hoc sense splitting in production.

Represent `criterion-ambiguous` as a study scoring status, separate from known/unknown-or-partial and from missing response. Do not silently map it to unknown or introduce a production evidence category. Whether ambiguous cases are excluded, bounded or analyzed separately—and how that affects coverage denominators—belongs in the approved SAP. Preserve both initial ratings, adjudication and reason codes; report agreement before adjudication and ambiguous/missing rates by subgroup/POS. Adjudication does not erase disagreement evidence.

Use randomized item order and alternate context-free delayed prompts, with schedules frozen in the protocol. Include adversarial rubric examples such as noun “bank” with financial/river senses and equivalent English/German examples. No AI grading defines the independent criterion.

**Acceptance:** raters can score a fabricated answer set without seeing model decisions; disagreements and alternative-sense cases resolve according to the rubric; access-control and export fixtures demonstrate that hidden context stays restricted; a documented protocol delta records the refined prompt/scoring semantics before confirmation.

## Relational consented study package

<!-- requirement: STUDY-PACKAGE -->

Extend the existing Core `ConsentedValidationStudyDataset` contract and offline validator through a versioned relational envelope or explicitly linked tables. Do not turn `VocabularyValidationStudyRecord` into a giant denormalized product record, and do not create a competing production persistence owner. Package/API names below describe proposed responsibilities; approve and freeze concrete versions before real collection.

| Table/responsibility | Minimum data required for the planned analyses |
| --- | --- |
| StudyParticipant | Pseudonym, consent protocol/status, language/L1/proficiency covariates, analysis split and cohort; no account identity |
| StudyDocument | Opaque study ID, content-equivalence/near-duplicate group, language/genre/format, inventory snapshot ID, eligible population and occurrence denominator; no title/path/raw text |
| StudyAssessment | Unique assessmentID, participant/document links, condition, algorithm/model/observation/resource versions, prior-used and eligibility status, question count, stop reason, abandonment/lookup status, current/projected/conservative coverage, burden measures and session order |
| StudyItemPrediction | assessmentID + lexicalItemID, finalKnownProbability for every assessable item including unasked items, occurrence count, classification, final asked/evidence/skipped/excluded status and inventory link |
| StudyCriterionRecord | assessmentID/audit linkage + lexicalItemID + phase, criterion/rater/adjudication labels, ambiguity/missingness status, rubric version, audit inclusion probability and sampling-stage linkage |
| StudyQuestionTrace | assessmentID, question ordinal, lexical item, evidence/protocol, selectionType, pre-answer prediction, optional research assignment metadata, relevant exposure/reveal ordering and durations |
| StudyDeckSnapshot | assessmentID, snapshot ID/version, proposed versus user-edited/imported deck role, selected membership, target and coverage summaries, learning/retest linkage |
| Sampling/retest manifests | Full frame or reconstructible frame hash and permitted artifact, strata and design version, inclusion probabilities for each stage, seed provenance, elapsed retest interval/window and missingness |

Use `participantPseudonym`, `opaqueStudyDocumentID`, `assessmentID`, `lexicalItemID` and explicit snapshot/phase IDs as joins. Multiple assessments of one participant/document must not collide. Selected flags in a prediction table are projections of the identified authoritative deck snapshot, not separately mutable truth. Define whether pre-reading criteria can be reused across assessments and under what exposure/time conditions; absent a frozen rule, do not reuse them.

Separate consented raw-response/rater materials from minimized analysis exports. Record enough timing to establish pre-reveal and retest-window validity using durations/relative sequence where possible, without exporting exact product timestamps. Define retention, access roles, withdrawal/deletion propagation and audit provenance for joins. Never hash product titles/paths as a substitute for opaque study IDs.

Validator checks must include schema/protocol versions, finite probabilities, positive occurrence counts, valid inclusion probabilities, referential integrity, unique keys, inventory/deck consistency, missing statuses, adjudication, ordering, participant/document/near-duplicate split disjointness and consent. A near-duplicate group cannot be reconstructed from opaque IDs alone: the restricted curator must provide the frozen equivalence mapping. Loading old datasets must either preserve compatibility or produce an explicit version/migration error; never silently invent missing endpoint inputs.

**Acceptance:** Swift serialization and offline validation agree; unasked-item predictions and denominators are available; wrong deck versions, duplicated keys, broken joins, missing probabilities, invalid weights and split leakage are rejected; privacy fixtures fail if forbidden product fields appear. Ordinary research export retains its current minimal schema and cannot claim document-held-out validation.

## End-to-end study rehearsal

<!-- requirement: STUDY-REHEARSAL -->

Build a small entirely fabricated study package before requiring confirmatory recruitment. Include English/German, a small-document census, a large-document probability sample, cold/warm assessments, natural and edited decks, immediate and delayed phases, disagreement/adjudication, ambiguity, nonresponse, abandoned sessions and insufficient subgroup support.

Create the data so an independent hand calculation or separate reference implementation knows the intended endpoint values. The only inputs to the analysis must be the serialized package and explicitly versioned analysis configuration; no hidden app state, private local files or convenient in-memory joins.

| Endpoint family | Required inputs and rehearsal proof |
| --- | --- |
| Item calibration | Frozen final predictions + uncontaminated pre-reading criterion + sampling design; compute Brier, log loss, reliability diagram/ECE and calibration slope/intercept where estimable |
| Deck precision/recall | Identified deck membership, pre-reading unknown criterion, occurrence weights and audit design; distinguish item precision from occurrence-weighted unknown recall |
| Coverage/miss rate | Full eligible occurrence denominator, observed criterion/retest outcomes and sampling design; distinguish census coverage from estimated coverage and model projections from realized learning |
| Burden and failures | Assessment condition, question/stop counts, elapsed phases, lookups and abandonment; expose missing rather than successful-only sessions |
| Warm comparison | Participant/document linkage, prior condition and history, paired/design metadata; compute the configured non-inferiority contrast |
| Raters, DIF and subgroups | Original ratings/adjudication, item/evidence data, L1/proficiency and independent learner support; report non-estimable cases instead of fabricating a fairness claim |
| Retention | Valid immediate/delayed links, elapsed interval and attrition; never count a missing retest as demonstrated retention |

Before SAP approval, any estimator/interval used for this rehearsal is explicitly provisional, versioned and labeled developmental. Do not quietly freeze Horvitz–Thompson, Hájek, bootstrap, sandwich or any other choice through an implementation default. Once the SAP is approved, rerun the same package with the approved methods and freeze expected outputs. A schema-valid package alone does not pass the analysis rehearsal.

For sampled documents, the event “actual coverage below 98%” is not the same as a plug-in coverage estimate below 98%, or a lower confidence bound below 98%. The SAP must specify how within-document sampling uncertainty enters the population miss-rate claim; retain an indeterminate status if its method requires one. Likewise, true global oracle deck regret is available for synthetic truth or an adequate census, not automatically for a sparse audit.

Negative controls deliberately introduce post-reveal criteria, invalid/changed weights, duplicate participant/document records across splits, near-duplicate document leakage, absent unasked predictions, contradictory deck snapshots, missing retest links and insufficient support. Each must fail or produce the prescribed non-estimable outcome. Preserve provisional analyses and deviations instead of selecting favorable estimators.

**Exit condition:** every proposed primary endpoint has an explicit input map and executes with independently checked expected behavior, or is visibly blocked by a documented decision. Confirmation remains blocked until primary endpoint gaps are resolved under the approved SAP; the fabricated rehearsal is not real-learner evidence.

## SAP precision and endpoint decisions

<!-- requirement: STUDY-SAP -->

Extend the existing SAP template with an explicit sample-size/precision section, then produce a separately reviewed actual SAP. Do not fill unknown decisions with invented numerical thresholds.

Require planned participant counts by language and stratum; document and near-duplicate-group counts; expected observations per participant/document/item; clustering and repeated-item structure; anticipated refusal/abandonment/nonresponse/ambiguous criteria and delayed-retest loss; minimum subgroup support; expected audited selected items and final-tail support; desired interval precision; coverage miss-rate precision; warm non-inferiority margin and required support; and sensitivity to the developmental assumptions used in planning. Independent learners per item, not total rows, govern empirical item calibration eligibility.

Retain all existing SAP decisions: estimands, populations, frame/inclusion probabilities and sampling stages, weighting estimator, weight trimming/normalization if any, participant/document dependence, variance/interval method, finite-population/small-sample treatment, adjudication uncertainty, missingness, multiplicity, outcomes/gates, holdout access, reproducibility and amendment procedure. Specify how repeated documents and history documents are kept inside the appropriate split; no participant or near-duplicate document may cross from development into confirmation through warm-history data.

Prepare an explicit endpoint decision for human theta-interval coverage. Preferred direction: retain literal true-theta interval coverage as a synthetic model-recovery metric and remove it from confirmatory human claims unless a credible independent latent reference is supplied. Alternatives are an anchored external calibrated instrument or a joint latent design with reference uncertainty explicitly modeled. This is a proposed `STUDY-002` amendment, not an implicit deletion. Human primary claims should emphasize observable item calibration, deck precision/recall, realized lexical coverage, nominal-target miss rate, burden and warm non-inferiority; statistical review freezes the actual primary/secondary/multiplicity structure.

A consenting developmental pilot may inform protocol feasibility, rubric behavior, pretest interference, timing and precision assumptions. It must be labeled developmental before collection and never promoted into the untouched confirmatory sample. SAP, protocol, scoring rules, analysis code/configuration, outcome gates and analysis populations must be reviewed/frozen before confirmatory data collection and inspection. Any post-freeze amendment retains its rationale, authorization and original analysis; no outcome-driven estimator choice.

## Human comparison and learning outcomes

<!-- requirement: STUDY-VALUE -->

Prioritize the simple baselines already named in the pilot: frequency threshold, select-all-unranked, frequency-only/generic Rasch, accumulated warm Rasch, and empirical-item variants only when permitted by their gates. The existing personal no-test blind audit can support exploratory within-reader diagnosis, but its self-report is not the independent study criterion and its answers must not train the reader prior or become confirmatory labels.

Compare preparation strategies under an explicitly defined equal total preparation-time budget, counting assessment, lookup/reading, review and residual waiting. Also retain ordinary product-use comparisons; do not infer usefulness from a shorter test alone. Freeze assignment/order/carryover handling and stopping for human comparisons in the protocol/SAP, especially because repeating the same document can itself teach words. Report unnecessary cards, capture of frequent unknowns, abandon rate, definition failures and time-to-useful-preparation alongside probability metrics.

Separate three outcomes: model-projected coverage assuming selected cards are mastered; immediate coverage after independently verified standardized learning; and delayed retention. Missing mastery or delayed outcomes never become mastered by assumption in realized-coverage analyses. Keep comprehension exploratory and independent of lexical coverage. No new Quick/Balanced/High-confidence modes, cold-limit reduction, alternative target or production selector is introduced by these comparisons.

## Calibration assignment approval package

<!-- requirement: CALIBRATION -->

Keep the reserved `calibration` path disabled. Study endpoint collection, randomized criterion auditing and calibration-purpose assignment are different mechanisms; they must have separate inclusion/assignment probabilities and must not block fabricated rehearsals unnecessarily.

Prepare the separately reviewable assignment package required by `CALDATA-001`: rate within the canonical 5–10% of scored questions, rounding/cadence policy at short sessions, eligible encountered-item pool, underrepresented ability-bin definition, bin boundaries and reconstruction, assignment policy, selection probabilities/support, exclusions/exhaustion/fallback behavior, policy version and the export schema needed to reconstruct or condition on assignment. Define whether/how calibration answers count toward existing question limits and tail validation without silently replacing those product contracts.

The minimum listed fields remain `questionOrdinal`, `selectionType`, `predictedKnownBeforeAnswer` and `thetaBinBeforeAnswer`; add policy/candidate-pool/propensity metadata if the chosen design requires it. Record the assignment-probability semantics and dependency on prior responses, rather than assuming four fields prove ignorability. Test an offline reconstruction from exported data. Freeze the concrete schema and assignment design before enabling slots or confirmatory collection involving them.

Include a feasibility calculation: 5–10% of 80 questions yields roughly four to eight assignments before cadence/rounding, often fewer in short warm sessions. Project independent learners per lexical item/ability group and document overlap, not only total response count. Do not lower pack eligibility (at least 100 independent learners, SE ≤ 0.35, reviewed bundled Rasch pack and no material unresolved DIF). Preserve separate L1/proficiency DIF, uniform/non-uniform effects, effect sizes, multiplicity, anchor purification and frozen minimum group support. Keep the Core-generated observation manifest/golden likelihood contract authoritative for the fitter; no new fractional-target fitting shortcut. 2PL stays disabled absent its held-out ≥ 0.01 log-loss gain and stable discrimination evidence.

**Acceptance:** approved design/schema permits faithful assignment reconstruction; privacy preview/export tests pass; support feasibility and sparse-cell behavior are explicit; no slot activates through a default setting, diagnostic flag or rehearsal fixture.

## Licensed POS fixtures and annotation mapping

<!-- requirement: POS-FIXTURES -->

Build pinned English/German Universal Dependencies fixtures with immutable source revisions/checksums, attribution/license files, source sentence IDs, genre and annotation-provenance metadata. Keep representative held-out documents/sentences distinct from development/adversarial tuning material. Follow source-specific redistribution terms rather than assuming every UD treebank has identical rights.

Useful starting references are [English EWT](https://universaldependencies.org/treebanks/en_ewt/index.html), [English GUM](https://universaldependencies.org/treebanks/en_gum/index.html), [German GSD](https://universaldependencies.org/treebanks/de_gsd/index.html), [UD licensing](https://universaldependencies.org/contributing/licensing.html), and [VerbForm](https://universaldependencies.org/u/feat/VerbForm.html). Verify the pinned releases when building. GSD is useful; its automatically assigned, unchecked lemmas must not be treated as unquestionable lemma/sense ground truth. Distinguish POS annotation provenance from lemma/morphology provenance and manually review a targeted adversarial subset with documented adjudication.

Freeze the UD-to-LeafReader POS mapping before held-out scoring, including AUX/VERB, proper/common nouns, conjunction categories, punctuation/nonlexical exclusions and unmappable tags. Participles are not a mutually exclusive POS class: use relevant morphological features and context under the mapping. Resolve token alignment, multi-word tokens, contractions, Unicode/UTF-16 ranges, German capitalization/compounds, and PDF dehyphenation before computing accuracy. Record alignment failures separately from POS abstention and lexical rejection.

Retain the production 0.65 leading-probability and 0.20 margin thresholds while evaluating. Produce diagnostic precision-versus-abstention curves on development fixtures if useful; do not choose thresholds on the held-out set. Freeze POS release decision criteria before inspecting held-out outcomes; no new numerical POS gate is chosen by this plan. Record macOS/Natural Language environment and rerun after relevant OS changes.

## POS to inventory to deck validation

<!-- requirement: POS-IMPACT -->

Evaluate three successive boundaries through `VocabularyDocumentLemmaIndex`, its `lemmaSummaries()` aggregation and `DocumentVocabularyInventory`, then downstream assessment/deck output:

1. Raw token tags: precision, recall, abstention, mapping/alignment failures and confusion matrices by language/genre, including noun↔verb and adjective↔participle-related errors.
2. Final lexical identity: lemma+POS split/merge errors after unknown-POS reconciliation, not just raw tagger correctness. Test a confident verb occurrence of “record” with an uncertain noun occurrence, and the reverse; include equivalent German homographs, multiple confident classes, only-unknown lemmas and line-wrap repairs. Preserve legacy wildcard migration and nil production sense keys.
3. Consequences: occurrence-weighted error, erroneous rejection/exclusion mass, denominator changes, difficulty changes, question identity and selected-deck changes. Compare predicted versus reviewed-gold inventories on fixed learner/evidence fixtures and report alignment limitations rather than manufacturing matching lexical IDs. Distinguish tag errors from normalization/grouping and native extraction errors.

Avoid treating every low-impact token error as a severe product failure, or a low aggregate error rate as sufficient safety. Report concentration on frequent homographs and contribution to coverage misses. Run corpus scoring independently from the simulator's synthetic 10% unknown-POS label share; synthetic labels do not exercise Apple's tagger.

**Acceptance:** metric denominators and abstention semantics are explicit at both raw and reconciled layers; split/merge fixtures detect a deliberately wrong grouping; consequence sums reproduce known occurrence changes; PDF and Web extraction parity is tested where relevant. Production POS policy changes, if evidence calls for them, require a separately reviewed bounded fix and regression tests, not silent tuning in the fixture builder.

## Usable-question latency instrumentation

<!-- requirement: UX-TIMING -->

Extend existing `ReaderPerformance`/`PerformanceEvent`, the preparation coordinator/view state transitions and capture validator. Do not build an unrelated telemetry system. Local opt-in measurements record durations/outcomes and bounded aggregate counts only, with no lexical content, typed answers, document identifiers or automatic transmission.

Instrument these separate monotonic-clock spans:

```text
answerTap -> learningContentVisible
continueTap -> nextWordVisible
continueTap -> nextWordAnswerable
knownVerificationTap -> nextWordAnswerable
```

Define endpoints by actual presented state and enabled answer controls, including completion of deferred exact work. Visibility alone does not complete the answerable span. Preserve phase durations for lookup, posterior update, question scoring, coverage completion and publication so regressions can be attributed. Do not include user reading time in a Continue-to-next span; retain end-to-end assessment/time budgets separately.

Trace known-correct prepared-branch adoption, partial/incorrect branch discard, unknown/unsure, prefetched versus failed lookup, Retry/Skip, early Continue, residual work, exhaustion and results. A terminal result is a distinct outcome, not a missing next-word success. Correlate locally using bounded request-generation identity, not persistent learner/document identity. Cancel or close spans on reset, navigation, document replacement and window closure; stale callbacks cannot finish a newer span. Avoid measuring state assignment alone if rendering/enabled controls have not reached the UI.

Report p50/p95/p99, maximum, sample count, missing/cancelled counts and raw durations by interaction, mode, cold/warm state and fixture. Specify percentile calculation and minimum support in the capture manifest; label p99 descriptive or insufficient when the sample is too small. The current 30-sample algorithm benchmark cannot substantiate a stable p99 by itself. Additional spans are diagnostic until separately reviewed thresholds are frozen; they do not weaken the existing 150 ms or 16 ms gates.

**Acceptance:** deterministic coordinator/state tests verify endpoint ordering and cancellation; real GUI capture confirms word visibility can precede answerability without ending the latter span; instrumented/uninstrumented comparisons quantify overhead; all retained exact branch and deferred-stopping parity tests still pass.

## Cross-format fixture and real-app matrix

<!-- requirement: GUI-FIXTURES -->

Create reproducible, redistributable English/German source texts and render each into PDF, EPUB and DOCX as supplemental fixtures. Pin source, generation command/tool versions, document checksums and expected inventories/occurrence counts. Include homographs, participial constructions, line wraps, compound/Unicode cases and enough lexical diversity for assessment transitions. Shared text enables direct cross-format comparisons and content-equivalence grouping; these six files are not six independent study documents.

Supplemental fixtures do not replace the required private English/German PDF/EPUB/DOCX manifest or representative scale/format edge cases. Keep private files/paths, raw study data and research exports out of git. Use `scripts/vocabulary_preparation_fixture_manifest.py`, the existing example manifest and `scripts/check_vocabulary_preparation_smoke.sh`; do not invent a second capture workflow.

In a logged-in macOS session with Accessibility permission, run both reader families with the injected German fixture dictionary and no network dependency. Capture inventory, assessment, result, import and document-visible-ready events; retain cold/warm, normal and early-Continue interactions, app/toolchain/OS/hardware metadata, control conditions, raw samples and all repetitions. Compare against the same-machine document-open control using the unchanged control + max(10%, 50 ms) tolerance and main-thread p95 ≤ 16 ms. Keep ordinary next-card, candidate-stop and final-result phases visible rather than hiding terminal work in an auxiliary bucket.

Use controlled run ordering and document/cache state; separate build/thermal/host-load effects from feature work and preserve unfavorable runs. Verify atomic idempotent import, existing-record protection, completion restoration and cancellation on PDF and Web paths. If opt-in, manifest or Accessibility is absent, report the environment blocker (the smoke wrapper uses exit code 3); it is neither a product failure diagnosis nor a pass. Fixture construction and static tests can proceed while GUI prerequisites are unavailable.

## Evidence register and documentation reconciliation

<!-- requirement: STATUS -->

Add a derived execution/status view without altering the canonical ledger's role or counts. For each outstanding requirement show canonical ID, behavior/claim, prerequisite, responsible capability, source revision/configuration, artifact/checksum, command/environment, gate, evidence class, current status, next action and decision history. Distinguish implemented, historically measured, verified on the current candidate, failed, awaiting external input, and deferred. Do not calculate “requirements completed” from the word active.

Reconcile the main testing guide and model explanation with the retained exact-optimization report. Older full/staged adverse timings remain historical evidence; latest passing exact microbenchmarks remain passing measurements with their revision/date. Real-app latency and final-tree acceptance stay visibly pending. The rejected selector/staged experiments remain accessible, and PR #9 refresh stays complete unless new evidence requires a factual correction.

Record all benchmark repetitions and failed/null experiment reports; retain version-2 golden and adverse version-3 holdout. A report must distinguish algorithm speed, usable UI latency, synthetic robustness and human calibration. Do not let a green schema validator stand in for an executable analysis, or a complete execution checklist stand in for release acceptance.

## Decisions and amendment boundary

<!-- requirement: AMENDMENTS -->

| Decision | Concrete preferred proposal | Approval/freeze point and work that can proceed |
| --- | --- | --- |
| Large-document audit | Predetermine criterion sample and estimate selected-card outcomes; retain small-document census | Explicit `STUDY-002` canonical/protocol/ledger amendment before its confirmatory use; fabricated design rehearsal can proceed |
| Human theta interval | Keep literal coverage in simulation; omit human claim absent justified latent reference | Explicit endpoint amendment and SAP review; preserve the existing requirement until that decision is recorded |
| Meaning prompt/ambiguity | Multiple context-free meanings, hidden target context for blinded raters, separate ambiguity status | Freeze protocol/rubric and any consent/schema delta before real use; fabricated scoring examples can proceed |
| Analysis package | Relational linked study records with complete endpoint inputs | Freeze versioned package/privacy contract before collection; no widening of ordinary product export |
| Estimation and precision | Named estimator/variance/missingness/multiplicity/design with justified participant/document support | Separately reviewed actual SAP before confirmatory collection or outcome inspection; provisional rehearsal methods clearly labeled |
| Calibration slots | Canonical 5–10% range; exact rate, assignment/bin policy and reconstructible schema | Separate approval before activation; diagnostic and criterion-audit work does not automatically enable slots |
| Diagnostic run design | Development seeds, B sample sizes/replicates, budgets, coupling and materiality/precision rules | Freeze run manifest before viewing its outcomes; routine reversible diagnostic implementation needs no new canonical approval |
| POS and usability decisions | Report required metrics and consequences; evaluate declared acceptance criteria | Freeze any new gates before held-out evaluation; no invented thresholds or automatic production tuning |

Prepare reviewable deltas against the accepted files, with affected requirement IDs, exact replacement text, compatibility/privacy effects and unchanged requirements. Do not rewrite the entire roadmap or call this companion canonical. A later explicit acceptance may authorize those deltas; elapsed time, generated files and an old approval record are not substitute approval. No permission question is required to finish the present planning task.

## Delivery sequence and ownership

<!-- requirement: ORDER -->

| Slice | Work and owner/capability | Dependencies | Reviewable output and exit |
| --- | --- | --- | --- |
| Foundation | Evaluation engineer: frozen development manifest, rich run identity, trace/denominator schemas | Inspect current source/tests and confirm immutable baseline | Synthetic trace fixtures, deterministic output, production-parity evidence |
| Forensic banks | Core/evaluation engineer: frozen-deck diagnostic seam, independent replicated banks, controls and missed-mass reports | Foundation | Reproducible A/B diagnostic report with uncertainty and no runtime behavior change |
| Counterfactuals | Core/evaluation engineer: natural/fixed-budget/common-sequence replay | Foundation and frozen RNG coupling; combine with bank reports | Tests for stopping bypass isolation and replay semantics; attributed/inconclusive results |
| Longitudinal priors | Core/store engineer with App integration review: real completion persistence, history scenarios, cold/warm comparisons | Foundation; counterfactual machinery for complete comparison | Disposable-db simulator, completion-contract tests, history and matched-budget reports |
| Study rehearsal | Research/data engineer and bilingual rubric reviewer: sampling timeline, relational package, fabricated analyses | May begin after contracts are mapped; does not wait for all synthetic gates to pass | Executable package and negative controls; concrete amendment proposals; no recruitment dependency for fabricated work |
| SAP/design | Statistical reviewer and study owner: precision, estimands, theta, pretest interference and consent | Rehearsal findings; explicitly developmental pilot where needed | Reviewed/frozen protocol, rubric, SAP and analysis code before confirmation |
| POS validation | NLP/fixture engineer plus bilingual reviewer | Pinned corpus/mapping and declared fixture split | Three-level metrics and consequence report; may run alongside study/synthetic work |
| Usable UI and GUI | App/performance engineer and operator with Accessibility/private fixtures | Instrumentation schema and state tests; private matrix needs environment | Four-span capture, same-machine control, six-document results and retained repetitions |
| Calibration package | Research/statistical reviewer and export engineer | Assignment feasibility and schema design; independent approval | Frozen policy/schema or explicit blocked/disabled disposition; no automatic enablement |
| Evidence reconciliation | Maintainer/reviewer | Cheap register scaffold at start; detailed updates after each slice | Derived status view and reconciled guides; preserve all historical evidence |
| Final acceptance | Release owner/reviewer | Required slices, explicit decisions and release prerequisites resolved; candidate frozen | Complete final-tree evidence and an honest pass/fail/blocked release decision |

Start with forensic diagnostics, then longitudinal warm simulation; prioritize fabricated study rehearsal next. POS fixtures and UI prerequisites can progress independently without competing for shared build caches or the live GUI. Use isolated worker outputs and serialize store/device/build mutations when required. The register is a low-cost aid, not a prerequisite that delays the scientific work. Concrete owners are assigned at implementation kickoff; roles here do not assert that participants, statisticians or permissions are already available.

Each slice is independently reviewable and testable. No arbitrary timeline or participant count is promised. If a diagnostic identifies a production defect, write a bounded finding with reproduction and proposed fix; implement it only within subsequently authorized scope and rerun the relevant guards. A negative study or unresolved synthetic miss is a valid result, not an excuse to relax a gate.

## Verification and final acceptance

<!-- requirement: VERIFY -->

Before each implementation slice inspect the relevant manifest, nearby tests and repository instructions. Extend existing owners/test suites rather than creating a parallel CAT or storage layer. Relevant locations include:

- Core: `AdaptiveVocabularyAssessment.swift`, `VocabularyMeasurementModels.swift`, `VocabularyReaderPrior.swift`, `VocabularyValidationStudyDataset.swift`, `VocabularyDocumentLemmaIndex.swift`, `VocabularyLexicalItemID.swift` under `Sources/LeafReaderCore/VocabularyReview/`.
- App: `VocabularyPreparationCoordinator.swift`, preparation view/panel and settings/export owners under `Sources/LeafReaderApp/VocabularyReview/`; `Sources/LeafReaderApp/App/ReaderPerformance.swift`; Core performance event/recorder definitions.
- Tools: `scripts/evaluate_vocabulary_assessment.swift`, `run_vocabulary_assessment_sensitivity.py`, `run_vocabulary_assessment_diagnostic_matrix.py`, `validate_vocabulary_validation_study.py`, `fit_vocabulary_calibration.py`, existing benchmark/capture/validator scripts.
- Tests: `AdaptiveVocabularyAssessmentXCTests`, `VocabularyMeasurementModelsXCTests`, `VocabularyReaderPriorStoreXCTests`, `VocabularyValidationStudyDatasetXCTests`, `VocabularyDocumentLemmaIndexXCTests`, `VocabularyResearchExportXCTests` in Core tests, and `VocabularyPreparationCoordinatorXCTests` / `VocabularyPreparationPersistenceXCTests` in `Tests/LeafReaderAppTests/`.

Run the narrow affected suites while iterating. All new diagnostic CLI/build paths must use Swift 6 and warnings-as-errors as required by the repository; verify wrapper invocation flags rather than assuming every existing standalone wrapper already enforces them. No broad production refactor or weakening of checks is justified by a planning or measurement task.

Representative existing commands (run only the affected subset during slices):

```sh
swift test --filter AdaptiveVocabularyAssessmentXCTests
swift test --filter VocabularyMeasurementModelsXCTests
swift test --filter VocabularyReaderPriorStoreXCTests
swift test --filter VocabularyValidationStudyDatasetXCTests
swift test --filter VocabularyDocumentLemmaIndexXCTests
swift test --filter VocabularyPreparationCoordinatorXCTests
swift test --filter VocabularyPreparationPersistenceXCTests
python3 scripts/validate_vocabulary_validation_study.py --self-test
python3 scripts/run_vocabulary_assessment_diagnostic_matrix.py --self-test
python3 scripts/run_vocabulary_assessment_sensitivity.py --self-test
./scripts/check_vocabulary_observation_model.sh
./scripts/test_vocabulary_assessment_evaluator.sh
./scripts/test_perf_capture_validator.sh
```

New CLI options/schema versions are specified and tested within their slice; the commands above do not pretend the proposed forensic, longitudinal or rehearsal tools already exist. Add meaningful regression/oracle tests for newly introduced failure modes and wire inexpensive deterministic checks into the existing suite; keep expensive diagnostic matrices explicit.

On the eventual final tree:

1. Resolve required amendment/SAP/consent and fixture/environment prerequisites. Freeze the candidate code, model/configuration/resources, study-analysis versions and intended release claims. Record commit, tree/dirty status, toolchain and artifact hashes. Source/model changes invalidate relevant prior evidence.
2. Run the development forensic, longitudinal, rehearsal, POS and interaction checks at their declared support. Diagnose failures on development material, not through a release-holdout tuning loop.
3. Run the complete evaluator and the frozen release holdout only after candidate freeze, preserving its original seed/population/gate definitions. New development suites are supplementary. Retain failed candidates and return to development if any gate fails; do not keep querying the same holdout while changing parameters to make it green.
4. Run controlled Release benchmark repetitions and real-app private six-document matrix with document-open controls and usable-state timing. Revalidate the 150 ms/16 ms/open-control gates; retain raw and adverse repetitions. Build the app as needed to produce the measured binary.
5. Run `./scripts/check.sh --no-build` for code changes and `./scripts/build_app.sh` for app/UI/resources/linkage changes and the final app handoff. Keep strict Swift 6/warnings-as-errors and unchanged native/Core checks. Ensure every report corresponds to the same final source/configuration; repeat affected evidence after any subsequent change.
6. Confirm required real-learner validation has been executed under the frozen protocol/SAP before making its gated claims. A successful fabricated rehearsal or synthetic suite cannot substitute. Any unfinished required item keeps the appropriate release/claim status blocked; distinguish readiness to collect data from readiness to release.
7. Review the evidence register, retain the adverse version-3 reports and version-2 golden until deliberate reviewed replacement is authorized after the required gates pass, and record the final acceptance decision. Do not re-publish PR #9 solely to repeat already completed work.

## Deliverables and completion checklist

<!-- requirement: HANDOFF -->

Each implementation slice hands off changed behavior, ownership, exact commands/results, source/configuration provenance, performance impact if measured, uncertainty, real limitations and the next decision. “Diagnostic tooling complete” does not mean “coverage failure fixed.”

- [ ] Failed-deck records conserve occurrence mass and account for answered/unasked evidence, difficulty residuals, flips and exclusions without overlapping causal claims.
- [ ] Frozen-deck independent-bank replicas, fixed-deck controls and convergence evidence distinguish sampling variability from systematic optimism; no bank B decision leakage.
- [ ] Natural, matched-budget and common-question/evidence replay comparisons preserve production behavior and expose their causal limits.
- [ ] Longitudinal priors use the real isolated store/completion path, coherent noisy histories, eligibility and failure cases; oracle-informed reference remains separately labeled.
- [ ] Large-document sampling amendment and pretest-interference design are concrete; small-document census, positive inclusion probabilities and pre-reveal timing are preserved.
- [ ] Relational study package supports full-inventory predictions, authoritative deck versions, denominators, missingness, relative timing, rater records and participant/document/near-duplicate holdouts.
- [ ] Multiple-meaning rubric, rater blinding, ambiguity and adjudication have executable examples and consent-compatible access boundaries.
- [ ] Fabricated census/sample/retest analyses and negative controls pass independently; unsupported endpoints remain explicit; final approved SAP analyses are rerun after freeze.
- [ ] SAP precision/sample-size planning, human theta endpoint decision, within-document coverage uncertainty and warm comparison design are reviewed before confirmation.
- [ ] Developmental human work stays separate; equal-time baselines, verified immediate learning and delayed retention are measured without conflating projection or comprehension.
- [ ] Calibration assignment feasibility, policy/rate/bin/schema approval remain explicit; disabled slots and empirical-model gates stay protected.
- [ ] Licensed POS fixtures and frozen mapping produce raw-tag, final-identity and consequence-weighted reports, including uncertain homographs, participles and erroneous excluded mass.
- [ ] Four usable-UI spans include p50/p95/p99 with support caveats, raw samples, terminal/cancelled outcomes and overhead; real-app control/main-thread gates remain separate.
- [ ] Reproducible cross-format fixtures supplement the private six-document matrix, with shared-content equivalence identified and realistic scale retained.
- [ ] Derived status view reconciles historical and current evidence, retains null/adverse results and marks PR refresh complete; canonical 42/12 ledger is unchanged except explicit future amendments.
- [ ] Final-tree checks/build, benchmark, GUI matrix, frozen holdout and required learner evidence support the recorded acceptance decision; no gate is weakened or golden replaced for convenience.

Open decisions belong to the named slice: development run precision/seeds/bank sizes and budgets; canonical study amendments; concrete study package versions; consented rubric/ambiguous-item treatment; sample design, estimator, variance and human sample support; participant/document recruitment and retest schedule; calibration slot policy/schema; POS decision criteria; usability sample support; and private fixture/Accessibility availability. They are explicit freeze procedures and external prerequisites, not silently chosen values or reasons to leave this implementation plan unfinished.
