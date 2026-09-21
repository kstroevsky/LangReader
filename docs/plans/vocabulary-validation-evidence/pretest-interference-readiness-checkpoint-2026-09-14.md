# Pretest-interference developmental readiness checkpoint — 2026-09-14

## Outcome

The developmental interference design is now executable at the assignment and
sequence-contract level, but real collection remains blocked. No participant
responses, outcome estimates, interference margin, sample size, estimator, or
approval were created.

The primary design randomizes lexical items 1:1 within participant and opaque
study document, stratified by predeclared frequency band and part of speech:

- criterion response before product-style response; or
- product-style response before criterion response.

The latter is the no-criterion-before-product control. Every assigned item gets
the first unaided product-style probe, so the intention-to-treat estimand does
not condition on whether an adaptive path later selects the item. Definitions,
context, correctness feedback, and response editing remain unavailable until
both responses are sealed. Study responses do not enter the production CAT.

The equivalence decision is structurally frozen: the approved confidence
interval for the criterion-before minus product-before correctness contrast
must lie wholly inside `[-interferenceMargin, +interferenceMargin]`. The margin
and all analysis/support choices remain null and block collection.

## Fabricated rehearsal

The deterministic no-outcome package contains:

- four fabricated participant-document blocks;
- four frequency/POS strata per block;
- two items per stratum;
- 32 unique assignments total; and
- exactly one assignment to each arm inside every block/stratum.

Negative controls reject allocation imbalance, response/outcome leakage, and
real-collection authorization. The package contains opaque fabricated IDs only,
with no word, response, definition, context, document text/title/path, or
participant data.

Fixture SHA-256:
`8871de2740a407ca29e60f8a5b68668e5cf0e6429a11b3daacc5668b9dab94bb`.

- [Blocked protocol](pretest-interference-development-protocol-v1.md)
- [Fabricated assignment package](pretest-interference-fabricated-assignment-v1.json)

## Remaining blockers

Before real developmental collection, statistical/research review must freeze
the practical interference margin, estimator, interval/confidence method,
small-sample and missing-data rules, sample size/power, minimum stratum support,
actual randomization seed, consent version, retention/deletion operations, and
named approval revision.

An equivalence result could only support submitting criterion-before-product
sequencing for confirmatory approval. Material interference requires split-
sample, order, or carryover handling. An inconclusive result keeps confirmatory
collection blocked. Development-confirmation and release holdout remain
untouched.
