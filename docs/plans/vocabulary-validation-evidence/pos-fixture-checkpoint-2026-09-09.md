# Vocabulary POS fixture checkpoint

Date: 2026-09-09

Base commit: `8f7091b`

## Outcome

The repository now has a pinned, reproducible English/German POS diagnostic that exercises the production 0.65 leading-probability and 0.20 margin policy, final lemma+POS reconciliation, inventory inclusion/exclusion, occurrence denominators, first-question identity, and selected-deck consequences. No production threshold, tag mapping, or POS behavior was tuned from the result.

`VocabularyPartOfSpeechConfidencePolicy` is the single Core owner for the existing confidence boundary; `VocabularyDocumentLemmaIndex` now calls it. `VocabularyPartOfSpeechReconciliationPolicy` exposes the existing rule that unknown occurrences join a lemma only when exactly one confident POS exists. Focused tests cover both threshold edges and noun-only, verb-only, multi-class, and unknown-only homograph cases.

## Fixture provenance

The checked-in fixture is generated from Universal Dependencies 2.18 test data and preserves repository/tag/commit, full source-file SHA-256, sentence ID, token ID, UPOS, XPOS, morphology, and occurrence weight.

- English EWT `r2.18`, commit `b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c`, source SHA-256 `fa024f43dc5da3c5ac02563bc9bd0e974f46cbb1560823976a8f342a37dc494a`, CC BY-SA 4.0.
- German GSD `r2.18`, commit `81d8c3612a88f5867fd089e9c0a5466ef230078b`, source SHA-256 `595070aa50b706a91dc66f17c296f7a9a25cbc75269f177c27680fb1c21528ab`. Annotations are CC BY-SA 4.0; upstream underlying-text terms and warranty limitations are retained in the attribution file.

The eight selected tokens include English/German participles, adjective/verb/noun ambiguity, German inflection, a proper name, and finite versus participial verb forms. This is an adversarial engineering excerpt, not a representative corpus sample. German GSD lemma annotations are not treated as unquestionable sense ground truth.

## Measured result

On the current macOS `NaturalLanguage` runtime:

- raw mapped-POS accuracy: 50.0%;
- abstention rate: 37.5%;
- final lexical-identity accuracy: 62.5%;
- occurrence-weighted final identity accuracy: 66.67%;
- confusion: adjective→noun 1, noun→noun 2, noun→unknown 1, verb→verb 2, verb→unknown 2;
- English gold/predicted occurrence denominator: 115/115, with four selected-deck identity differences;
- German gold/predicted occurrence denominator: 90/90, with two selected-deck identity differences;
- both first-question identities remained unchanged in this tiny fixture;
- tested proper-name exclusion was correct, with zero erroneous excluded/included mass.

The adverse cases are retained: English `record` was noun instead of UD adjective, English `recording` abstained and kept the surface as an unknown-POS lemma, German `laufen` abstained, and German proper-name `Bank` abstained but was still correctly excluded by the name boundary. These results demonstrate consequence sensitivity; they do not justify changing thresholds on eight selected tokens.

## Verification

- `swift test --filter VocabularyDocumentLemmaIndexXCTests` — 14 tests, 0 failures.
- `./scripts/test_vocabulary_pos_fixtures.sh` — two evaluator runs were byte-identical; report validation and negative controls passed.
- Fixture builder regenerated the checked fixture from the pinned remote files after verifying both full-file hashes.
- `./scripts/check.sh --no-build` — all checks passed, including strict Swift 6 build, 163 Swift tests with one expected private-fixture skip, 281 logic tests, evaluator suites, Core/native boundaries, and the POS fixture suite.

`./scripts/build_app.sh` was not run because no app assembly/resources/UI/native-reader behavior changed. NaturalLanguage output is OS-dependent and should be recaptured after a relevant macOS update.

## Artifacts

- [Pinned UD excerpt](../../../Tests/Fixtures/VocabularyPOS/ud-v2.18-selected.json) — SHA-256 `258f6220094afecd864aa0930824309509e43aef8b740192acb523133decaf3c`
- [Attribution and license notes](../../../Tests/Fixtures/VocabularyPOS/ATTRIBUTION.md) — SHA-256 `ae592ad873719a61e0f9279bcdc948a6860984312b079f185d299e7ee52a0b1b`
- [Machine-readable POS result](vocabulary-pos-fixture-report-v1.json) — SHA-256 `bd0d631ab9ff1b51adb7f67527edd3cd0885c7ee21e0bf6277facd136a02f57e`

## Decision

The infrastructure is working correctly, but the fixture result is too small and too adverse to support a POS release claim or a production policy change. The next POS action should be a larger predeclared development/held-out corpus sample with alignment review and frozen decision criteria. That expansion must preserve the pinned license/source mapping and must not tune on held-out outcomes.

The next independent plan slice after this checkpoint is usable-question latency instrumentation and GUI/private-document evidence; it requires the appropriate logged-in Accessibility/private-fixture environment for actual GUI capture.
