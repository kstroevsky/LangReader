# Representative POS validation checkpoint — 2026-09-12

## Status

The POS diagnostic has progressed from an eight-token adversarial probe to a
frozen 480-token UD 2.18 development/held-out evaluation. The result is adverse
engineering evidence, not a green POS release claim. Production confidence
thresholds remain 0.65 leading probability and 0.20 margin.

## Freeze and execution history

The first v1 reservation selected 80 UD dev and 160 UD test sentences per
language. Its first scoring attempt aborted before producing a report because
one upstream German token surface was absent from reconstructed sentence text.
V1 remains committed and consumed as a fixture-construction failure.

V2 requires a target surface to occur exactly once verbatim, uses a new
versioned selection order, and excludes all 320 v1 held-out case IDs. It retains
480 unique sentences: 80 development and 160 held-out cases for each of English
and German. English EWT covers answers, email, newsgroup, reviews, and weblog;
German GSD provides one mixed-web source stratum. All 13 supported UPOS classes,
proper-name exclusions, and participles occur in both language/split families.

The first v2 process computed case predictions but trapped during downstream
deck-consequence construction because repeated corpus lemma+POS rows had not
been aggregated. No result was emitted or inspected. The recorded mechanical
repair sums occurrence weights by lexical identity before constructing the
diagnostic assessment; it changes no predictions, fixture cases, or policy.

## Results

| Cell | Cases | Raw mapped POS | Abstention | Final identity |
| --- | ---: | ---: | ---: | ---: |
| Overall | 480 | 74.58% | 9.58% | 69.38% |
| English development | 80 | 76.25% | 5.00% | 72.50% |
| English held-out | 160 | 77.50% | 5.62% | 73.75% |
| German development | 80 | 72.50% | 15.00% | 65.00% |
| German held-out | 160 | 71.88% | 13.12% | 65.62% |

The held-out cells contain 27 missing/28 extra English identities and 38
missing/42 extra German identities. Their lemma/POS-set mismatch counts are 34
and 53. Held-out denominator deltas are -3 English and +3 German; erroneous
excluded/included masses are 7/4 and 1/4. The English held-out first question is
unchanged, the German one changes, and selected-deck symmetric differences are
57 and 81 identities respectively.

These results confirm that the earlier warning was not only an eight-token
artifact. They do not establish failure rates on representative private reader
documents, and no acceptance threshold was invented after viewing outcomes.

## Evidence integrity

- The fixture builder pins UD release revisions and dev/test SHA-256 values.
- Repeated v2 builds are byte-identical; held-out overlap with v1 is zero.
- The report records fixture ID/SHA, macOS 15.7.9 build 24G830, all 480 case
  results, group metrics, split/merge summaries, denominators, question identity,
  and deck consequences.
- Validators recompute all aggregate/group metrics and consequence accounting,
  reject threshold changes, duplicate cases, corrupt support, non-verbatim
  surfaces, split overlap, and premature held-out status changes.
- The ordinary eight-token diagnostic remains retained and no production POS
  policy or CAT configuration changed.

## Next action

Use only the development partition for root-cause work. Any proposed bounded POS
or lemma fix must receive regression coverage and a newly reserved held-out set;
v2 is now consumed evidence and must not become a tuning loop. Representative
private PDF/EPUB/DOCX validation remains separate.
