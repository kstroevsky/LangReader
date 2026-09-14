# Vocabulary repeat-response dependence protocol v2

Status: **production-event aligned; real collection blocked**.

This v2 addendum supersedes v1 for future collection while retaining v1 by
checksum for unchanged rater, transition, dependence, missingness, privacy, and
access contracts.

`E1` and `E2` now each mean the complete production event:

1. show lemma+POS and the first-stage actions `I know it`, `Not sure`, `I don’t
   know`, and separate `Not a word/name` exclusion;
2. retain optional typed meaning before reveal;
3. an `I know it` choice enters pending verification and records no evidence;
4. reveal the frozen product definition;
5. map `My meaning was correct` to `verifiedKnown` when no typed meaning exists
   or `typedVerifiedKnown` when it does; map `No / only partly` to
   `verifiedUnknownOrPartial`;
6. map `Not sure`, `I don’t know`, and exclusion to `unsure`,
   `reportedUnknown`, and `excluded`; and
7. after the frozen distractor/delay protocol, repeat the same complete event
   for `E2`.

The pre-second-reveal response is not an unaided baseline because the E1 reveal
has already occurred. The estimand deliberately includes resulting learning,
cueing, and carryover under this operational protocol.

Baseline `K` remains two-rater adjudicated target-meaning correctness from an
approved independent pre-reveal criterion path. Real collection cannot begin
until the v2 pretest-interference study supports equivalence or an approved
split-sample/order/carryover design supplies `K` without silently assuming the
criterion inert.

The primary estimand is:

`p_persist = Pr(E2 supports known | E1 supports known, K = unknown, production-aligned protocol)`.

Its denominator is **distinct eligible participant-item records**, not
independent records. Participant, document, and item dependence remains
mandatory. All v1 timing, estimator, precision, sample-size, missingness,
consent, and governance fields remain null; v2 adds null production-UI,
evidence-mapping, baseline-K, and full-E2 version fields. Collection, holdout,
and production authorizations remain false pending independent approval.
