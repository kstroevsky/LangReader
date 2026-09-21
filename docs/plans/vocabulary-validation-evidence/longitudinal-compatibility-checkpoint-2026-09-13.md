# Longitudinal current-document compatibility checkpoint — 2026-09-13

## Decision

Reject `paired-validation-evidence-log-likelihood-ratio-v1` at its frozen zero
threshold and retain the current production behavior. Do not tune this threshold
from the consumed result.

## Execution integrity

- The reservation was frozen in commit `605f842` before implementation or
  outcome execution.
- Diagnostic implementation and the derived evaluator manifest were committed
  at `c77f732367d2c75dea45fd36e1b13d1a99d2c92b` before the single run.
- The semantic report records a clean source tree at that revision.
- All 1,024 planned rows were retained. Four hard-history/easy-evaluation rows
  were naturally ineligible because their three completed histories accumulated
  only 37, 27, 14, and 20 verified evidence records, below the production
  threshold of 40. They remain in the report and are excluded only from the
  eligible-policy summary.
- Development-confirmation, release-holdout, consumed POS held-out, user-store,
  and production-activation access remained forbidden.

## Frozen result

Among 1,020 eligible rows:

| Policy | Mean warm-cold coverage | Worst warm-cold coverage | Material tails | Mean question reduction |
| --- | ---: | ---: | ---: | ---: |
| Current production count-only relaxation | -0.1830 pp | -15.9906 pp | 55 | 72.019% |
| Frozen likelihood-ratio candidate | -0.1391 pp | -15.9906 pp | 54 | 68.934% |

The signal supported the eight-question relaxation in 721 rows, rejected it in
284, and lacked two non-excluded validation answers in 15. The 20-question
counterfactual applied to 242 rows. It eliminated four production material
tails but introduced three different material tails.

The candidate passed the predeclared mean coverage and mean question-reduction
screens. It failed the primary requirement of zero losses worse than two
percentage points, leaving the same -15.99-point worst case. The conjunctive
decision is therefore failure.

## Interpretation

A two-answer likelihood ratio at threshold zero is not a sufficient compatibility
gate. It modestly improves the pooled mean but does not control the dangerous
tail and can move failures between learners. This adverse result does not imply
that warm personalization should be disabled globally, nor does it justify a
different threshold selected on these outcomes.

The result also confirms that the current product's two validation answers are
only a support-count condition for the shorter minimum; agreement is not
required. That production rule was deliberately left unchanged in this slice.

## Verification and artifacts

- Schema-3 longitudinal validator self-test passed, including corrupted
  likelihood, candidate coverage, replay mass, and evidence-path controls.
- Core regression confirms the diagnostic probability seam is read-only and
  the production warm-minimum rule is unchanged.
- Semantic report SHA-256:
  `789542ee581b315a4e6ed330c9dd855e2f7eef276f95481289a9a2f8db8a5e41`.
- [Frozen reservation](longitudinal-compatibility-development-manifest-v1.json)
- [Semantic JSON](longitudinal-compatibility-development-report-v1.json)
- [Concise evaluator report](longitudinal-compatibility-development-report-v1.md)
- [Decision analysis](longitudinal-compatibility-development-analysis-v1.md)
- [Raw timings](longitudinal-compatibility-development-timing-v1.json)

## Next boundary

Do not bind development-confirmation to this candidate. Any new compatibility
signal, additional validation question, changed threshold, or minimum policy is
a new design and requires a fresh frozen development reservation. The current
evidence supports investigation of why early warm paths select harmful evidence,
not a release change.
