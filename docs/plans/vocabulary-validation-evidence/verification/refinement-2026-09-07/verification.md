# Bounded-refinement verification

Status: mechanical, semantic and independent forward verification PASS. Finalized on 2026-09-08. This is documentation-only evidence and does not claim implementation, tests of production code, diagnostic measurements or release acceptance.

- Locked reviewed plan SHA-256: `643159fae7c981d6efab48cc0f48a2d6d176f215cd7298ee4221735976e80d15`.
- Candidate plan SHA-256: `93100e889355145526f75f0347ee9b835185a7aa9458929db951d2f24607e05f`.
- Exact patch operations: 37; feedback items F01–F07 incorporated.
- Changed Markdown sections: 12; added/removed sections: zero; unexpected changes: zero.
- Execution ledger counts: 25 active, zero deferred, zero superseded, unchanged. Amended existing IDs: SCOPE, DIAG-BANK, DIAG-PAIR, STUDY-SAMPLE, STUDY-RUBRIC, STUDY-REHEARSAL, STUDY-SAP, STUDY-VALUE, AMENDMENTS, ORDER, VERIFY, HANDOFF. No execution ID added or removed.
- Canonical ledger remains 42 active / 12 deferred. Canonical roadmap, ledger and acceptance hashes match the original source lock. The original verification folder's existing files remain untouched.

## Exact delta

| Feedback | Bounded change |
| --- | --- |
| F01 | Distinguish A, B1 and B2; preserve A; separate theta-position/latent-item RNGs and fingerprints; require B1 exact deterministic theta strata and B2 independent randomized/shifted strata; preserve B1 stratum weights for larger replicated banks; retain separate comparisons, controls and uncertainty. |
| F02 | Add diagnostic-development → fresh untouched development-confirmation → frozen release-holdout ordering. Freeze candidate/configuration/analysis/rules before intermediate access; retain failures, return to development and require a fresh intermediate set after redesign. Reserve manifests only in the future first milestone; do not access confirmation or release outcomes there. |
| F03 | Pretest interference now explicitly blocks confirmatory collection until evidence supports the procedure or the reviewed design accounts for it. Developmental measurement remains allowed. |
| F04 | Remove the target-sense freeze feasibility exception; freeze target-sense/context mapping and rubric before confirmatory response/model-outcome inspection; use frozen ambiguity and amendment handling afterward. |
| F05 | Separate core human validity and broader equal-total-preparation-time comparison. Only an identified authoritative prerequisite can make the latter block core validity; preserve baselines, standardized learning and retention where required by the relevant endpoint. |
| F06 | Add minimum inclusion probability, maximum weight, effective sample size and expected selected-card/final-tail support in sampling design, rehearsal and SAP decisions; require explicit definitions/grouping; add no numerical thresholds, estimator or trimming defaults. |
| F07 | Specify the first future synthetic causal-diagnostics milestone, direct counterfactual dependencies, excluded work and review checkpoint. Honor latest stop-before-code instruction: current task is documentation and implementation handoff only. |

## Mechanical and preservation checks

`mechanical-verification.json` records plan_guard PASS: base hash, section allowlist, required anchors, ledger transition and exact-contract checks. No numerical contract was removed; the sole added numeric token is `2` in the RNG/data-separation section's preserved version-2-golden reference. No versioned contract token, code fence or display-math signal was added or removed. All other sections are byte-identical to the locked base.

`patches.json` contains every exact replacement; `apply_refinements.py` reconstructs the candidate from the locked base, never from the last candidate. `original-ledger.json` preserves the prior ledger bytes. `base-ledger.json` normalizes only the top-level base hash for this revision; all original requirement records are identical. `verify_refinements.py` derives the enriched target ledger and runs the guard. These are documentation-preservation utilities, not product/diagnostic implementation.

`negative-controls.json` proves four invalid candidates are rejected: changed production predictive count, deleted mandatory rubric-freeze anchor, unapproved preserved-ledger mutation and deleted deferred contract. `source-lock-check.json` proves all three canonical source hashes and 42/12 counts remain intact.

## Semantic passes

- **Delta:** all seven feedback groups are explicit in operational sections, decision table, delivery boundary and relevant checklist entries; B1/B2 are not conflated into a single bank estimate.
- **Preservation:** original model, likelihood/evidence reliabilities, denominators, release gates, production samples, cold/warm limits, exact optimizations, privacy, ownership, reader seams, deferred conditions, baseline adverse results and PR #9 status remain intact. Warm-history, POS, calibration, GUI and timing detail remain present but outside first-milestone execution scope.
- **Exact contract:** the original mass equations, gate table, quantified model conditions and twelve deferred IDs are unchanged. Candidate sample sizes remain illustrative rather than production defaults. New sampling diagnostics defer numerical values to SAP/design freeze.
- **Negative control:** no study-data schema or production model/policy change is authorized here; broader product-value separation cannot waive an existing canonical prerequisite; randomized criterion audit does not activate calibration slots.
- **Cross-interface:** A freezes deck/state before B1/B2 evaluation; stream separation preserves deterministic B1 theta positions; evaluation never feeds production choices. Development-confirmation access follows candidate freeze and precedes release holdout. Confirmatory collection additionally requires the pretest decision, SAP and unqualified scoring freeze. Core validity completion is distinct from broader product value.
- **Standalone:** original authority hashes/contracts and full minor-improvement details remain available in the plan; the future checkpoint enumerates every requested output and requires stopping for review. Root-authored implementation-handoff.md supplies the separate mode prompt and is not modified by this preservation patch.

## Independent review

Independent reviewer `refinement_review` re-read the locked base, user feedback, candidate, delta, structured target ledger and implementation handoff. It independently replayed all 37 patches and verified exact reconstruction, authorized ledger transitions, canonical hashes/counts, preserved minor requirements and scientific/scope consistency. Final verdict: **PASS**, with no open findings.

One handoff-only wording issue was repaired: “small-enumeration or independently hand-calculated oracle fixtures” could have made enumeration optional. The prompt now requires “small-enumeration oracle fixtures with independently hand-calculated/reference expectations.” The reviewer verified closure. This repair did not alter the plan, its candidate hash or the 37 plan patches.

The [implementation handoff](../../implementation-handoff.md) is the detailed prompt for another mode. Its SHA-256 is recorded in `revision-state.json`. Current task remains documentation-only; no implementation code or tests were written. Existing evaluator baseline output was captured before the user's stop instruction for pre-change characterization (seed 42, two readers, two documents, 60 lemmas). That small run is gate-ineligible and is not release acceptance or an implementation of the new diagnostics. No release holdout, confirmatory data, participant data or GUI was accessed.

Fresh completion checks passed: plan_guard mechanical verification, canonical source locks, document links/fences/whitespace, and `git diff --exit-code -- Sources Tests scripts Package.swift`. Only the user-requested untracked plan directory is present in the working-tree status. Full product checks/builds are left to the future implementation slice.
