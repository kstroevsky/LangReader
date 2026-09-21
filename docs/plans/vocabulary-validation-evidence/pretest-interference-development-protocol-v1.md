# Vocabulary pretest-interference developmental protocol v1

Status: **design defined; real collection blocked**.

This additive protocol operationalizes the approved developmental interference
study without changing the production assessment or authorizing participant
collection. Its purpose is to estimate whether answering the independent
criterion first changes the first unaided product-style response for the same
lexical item.

## Randomized order design

Eligible items are randomized 1:1 within participant and opaque study document,
stratified by predeclared frequency band and part of speech:

- `criterion-before-product`: criterion response, then product-style response;
- `product-before-criterion`: product-style response, then criterion response.

The second arm is the no-criterion-before-product control. Both responses are
collected so criterion support is not lost, but no definition, document context,
correctness feedback, or response editing is allowed until both tasks finish.

Every randomized item receives the fixed product-style probe. This avoids
conditioning the primary comparison on whether an adaptive assessment happens
to ask the item after assignment. Responses do not enter the CAT, and the fixed
probe does not claim full transportability to a natural adaptive session.

Both tasks show lemma and part of speech and request one or more context-free
meanings or translations. Two blinded raters receive the restricted target
sense/context, adjudicate disagreement, and preserve `criterion-ambiguous`
separately from missing.

## Estimand and decision

The primary item-level outcome is adjudicated target-meaning correctness of the
first product-style response before reveal. The intention-to-treat contrast is:

`criterion-before-product - product-before-criterion`.

Interference equivalence is supported only if the approved confidence interval
lies wholly inside:

`[-interferenceMargin, +interferenceMargin]`.

The margin, estimator, interval, confidence level, small-sample adjustment,
missing-data rule, sample size/power, minimum stratum support, and actual
randomization seed remain unapproved. No result may be inspected before they are
frozen. Material interference requires split-sample, order, or carryover
handling in the confirmatory design; an inconclusive result keeps confirmatory
collection blocked.

## Fabricated rehearsal boundary

A deterministic no-outcome rehearsal may use four fabricated
participant-document blocks, four strata per block, and two items per stratum.
It proves 1:1 assignment balance, concealment fields, sequencing, and schema
validation only. It contains no real responses and cannot estimate interference.

Real collection additionally requires explicit consent, retention/deletion
operations, an executable frozen assignment/analysis package, and named
approval. Normal product exports, automatic upload, raw document text/title/path,
exact product timestamps, ordinary user databases, development-confirmation,
and release-holdout access remain outside this protocol.
