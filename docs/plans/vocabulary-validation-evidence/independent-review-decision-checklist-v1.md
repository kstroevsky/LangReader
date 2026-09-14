# Vocabulary independent review decision checklist v1

Status: **ready for review; all decisions unapproved**.

The independent statistical/research/privacy reviewer must resolve:

1. the practical known-claim interference margin and inferential method;
2. a decision-relevant equivalence guardrail for the complete non-exclusion
   first-stage distribution, including method, margins, uncertainty,
   multiplicity, and minimum support;
3. baseline criterion-`K` acquisition, misclassification/error treatment,
   rater uncertainty, and sensitivity when conditioning on `K=unknown`;
4. immutable production UI and evidence-mapping versions;
5. repeat confirmation wording, definition presentation, distractor count,
   maximum delay, and precision/support for distinct records with `K=unknown`
   and known-supporting `E1`;
6. one formal conditional tail-severity endpoint; and
7. sample size, clustering, missingness, consent, retention/deletion, named
   approvers, and approval revision.

For item 6, when `c_severe < 0.98`:

`conditionalTargetShortfall = (0.98 - c_severe) + conditionalThresholdExcessSeverity`.

The two conditional metrics therefore differ by a known constant after the
severe threshold is fixed. Choose one formal release severity endpoint rather
than treating both as independent evidence.

Every decision value remains null in the machine-readable checklist. Review,
collection, confirmation, holdout, and production authorizations remain false.
A separately versioned approved review record is required to change them.
