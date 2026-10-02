# Representative-Book Validation Experiment v1

Status: **development / pre-confirmatory**. The corpus roles and source hashes are frozen. Human gold and non-inferiority margins are not yet frozen, so confirmatory A/B/C execution remains blocked.

## Checkpoints

The experiment compares three immutable software revisions under one runtime and one frozen sample bundle per document:

| Checkpoint | Revision | Meaning |
| --- | --- | --- |
| A | `d74a198551f437814b6f305342c235523ecf8df3` | pre-ADR-0001 baseline |
| B | `ac321721cdd52d966cc859040106feb544a67735` | final ADR-0001 / PR #12 head |
| C | `970b049d7aa3a0770c6b9dfa84e6b40e6e327da9` | ADR-0002 / PR #13 head rebased on B |

`B` is an ancestor of `C`. The A/B/C exporter compiles each historical Core revision from a `git archive`; it does not mutate the working tree or back-port newer semantics into A.

## Corpus and role freeze

The canonical source list is `representative-book-corpus-manifest-v1.json`. It currently freezes 70 PDF/EPUB files by SHA-256 from `~/Desktop/books`: 20 development and 50 confirmatory. Both roles contain English, German, PDF, and EPUB strata.

Role assignment is source-structure based and was performed before checkpoint predictions:

- standalone `en/` and `de/` cohorts are development;
- the paired `en+de/` cohort is confirmatory;
- Patrick Radden Keefe and Saša Stanišić stay development because the same work families already appear in the standalone development cohort;
- translations in one work family may not cross roles;
- confirmatory documents may use only the prediction-independent representative panel.

The generated `representative-book-holdout-manifest-v1.json` is the confirmatory subset. It contains metadata and hashes only, never extracted prose.

## Sampling and local artifacts

`build_vocabulary_representative_book_candidates.swift` supports PDF and EPUB with two explicitly different policies:

- `representative-book-challenge-v3` is development-only and may use NaturalLanguage lemma/POS output to prioritize likely failure cases;
- `representative-book-representative-v2` groups and orders candidates only from source position, canonical surface, and deterministic hashes. It does not inspect lemma/POS predictions and is the only permitted confirmatory policy.

Both policies sample PDFs across readable PDFKit pages rather than sampling all page indexes and silently dropping empty pages. Original PDF page numbers and total page count remain frozen in provenance. EPUB continues to use `epub-paragraph-pack-v1` units from the production `WebDocumentLoader`.

EPUB text comes from the production `WebDocumentLoader`; PDF text comes from PDFKit. Schema-v2 provenance records the source hash, extraction-unit policy, unit count, sampled unit numbers, and sampled-text hash. Annotation templates and sample bundles contain copyrighted prose and therefore remain local. Safe metadata and corpus manifests may be checked in.

`materialize_vocabulary_representative_book_fixture.swift` still accepts the existing schema-v1 Martin Eden development annotations and also accepts schema-v2 PDF/EPUB annotations. Approved rows are aligned to exact Core occurrence ranges. Human gold lemma/POS remains authoritative.

## Human annotation protocol

Development annotations may be iterated. Confirmatory gold must be created before any A/B/C predictions are shown to annotators. Confirmatory annotators should be blind to checkpoint outputs and ideally independently double-annotate disagreements before adjudication.

Rows with extraction/alignment errors must be rejected rather than forced into a lexical label. The materializer accepts only `approved` rows. A failed hash/range/surface check is a provenance failure and must be fixed by regenerating the source artifact, not by manually moving an occurrence.

## Common checkpoint export

`run_representative_book_checkpoint_exports.py` consumes one or more frozen local sample bundles and emits the same version-neutral schema from A, B, and C. In batch mode it compiles each historical checkpoint once and reuses that immutable exporter across documents; it does not rebuild Core for every book. Common fields include source range, surface, requested/detected/routed language where available, lemma/anchor, predicted POS, final resolved lexical key, resolution state, assessment identity policy, context fingerprint, evidence providers, reconciler version, and source/runtime provenance.

Every raw checkpoint export records the macOS version/build, machine architecture, Xcode version, Swift version, NaturalLanguage runtime signature, language-selection mode, dictionary-attestation state, and SHA-256 of the experiment harness. The analyzer refuses to aggregate books/checkpoints whose OS/build/architecture/Xcode/Swift signature differs and refuses a checkpoint whose harness hash changes between books.

Fields that did not exist in A are emitted as null. A is not made to emulate ADR-0001. B emits lexical reconciliation but no ADR-0002 language detection. C additionally records Apple language recognition and uses the C linguistic adapter; an unresolved C language probe degrades to exact-form evidence for the lexical pass.

Sample bundles also carry the exact annotation SHA-256 and candidate-selection policy. Confirmatory execution is mechanically blocked unless a separate confirmatory freeze record says `status: frozen`, contains the exact A/B/C revisions, hashes the corpus manifest, gold manifest, and analysis rules, and lists the exact source/annotation/sampled-text tuple for the bundle being executed. This prevents a post-freeze document or re-annotated sample from being slipped into a confirmatory run.

## Gold, analysis, and freeze boundaries

`build_representative_book_gold_manifest.py` creates a prose-free manifest from local schema-v2 annotation files. Gold manifests are panel-scoped: development requires an explicit `challenge` or `representative` panel, annotations from the other panel are ignored, and the two development panels must be analyzed separately rather than averaged into one book-accuracy estimate. A frozen manifest rejects unreviewed occurrences and, for confirmatory data, requires the complete role-frozen corpus and the representative sampling policy.

`analyze_representative_book_checkpoints.py` is the pre-holdout executable analysis boundary. It matches approved gold to A/B/C by physical UTF-16 occurrence range, reports resolved coverage, joint lemma/POS correctness, B³ partition metrics, pairwise false split/merge rates, split precision/Wilson intervals, document/work/language/genre/format summaries, and paired work-family bootstrap deltas when the replicate count has been frozen. It deliberately reports the routing, NLP-degradation, assessment-path, and controlled cross-format checks that are not inferable from natural-book occurrence exports as not measured rather than silently treating them as passes.

`freeze_representative_book_experiment.py` refuses to create a confirmatory freeze while the analysis rules still contain unfrozen non-inferiority margins, bootstrap count, stratification, missing-data policy, enrollment/stopping rule, or retry policy. The freeze hashes the analysis code itself as well as the corpus, gold, analysis rules, and the exact A/B/C checkpoint-export harnesses. Confirmatory execution and analysis both reject an exporter-harness mismatch.

## Analysis plan before holdout opening

Fixed hard gates from ADR-0001 are:

- automatic split precision >= 98%;
- two-sided Wilson 95% lower bound >= 95%;
- automatic splits when NLP is unavailable = 0.

ADR-0002 routing invariant counters are expected to remain zero. The confirmatory report must present both micro summaries and document/work-level macro summaries, with predeclared stratification by language, genre, format, work family, gold single/multi-POS partition, and occurrence-count band (`2–3`, `4–7`, `8+`; a residual `1` band may appear after unusable occurrences are rejected). Paired A/B/C deltas use a work/book-cluster bootstrap; translations from one work family must remain in the same resample cluster.

Numerical non-inferiority margins for requirements such as “false merges must not materially worsen” are intentionally not invented here. They must be justified from development evidence and product consequences, then frozen before confirmatory results are opened. The final freeze also records bootstrap replicate count, planned stratification, missing-data policy, stopping/enrollment rule, analysis-code SHA, corpus-manifest SHA, and human-gold-manifest SHA.

The confirmatory enrollment rule itself is already outcome-independent: execute all 50 sources in the frozen holdout for every checkpoint, with no early stopping and no post-output document addition/removal. The protocol's `250+` predicted automatic-split figure is retained as a practical evidence-adequacy target, not as a data-dependent stopping rule. If the frozen holdout produces fewer than 250 such decisions, report that limitation rather than extending the same holdout after seeing results. Ambiguous/unresolved checkpoint output remains an observed model outcome in the denominator; only infrastructure failures may be retried under the frozen retry policy.

## Format and degradation checks

Natural-book evidence reports PDF and EPUB separately as well as pooled. Synthetic cross-format fixtures remain the controlled parity test; natural books are not assumed text-identical across editions/translations. NLP-degradation testing must explicitly remove linguistic evidence and verify that unresolved/direct-evidence behavior does not create automatic splits.

## Relationship to existing reservations

The existing v17/v18 vocabulary reservations are separate evidence programs. This corpus does not consume v18 merely because the representative-book tooling is ready. `development-confirmation-reservation-v18.json` remains sealed/unexecuted until its own release conditions are satisfied.

## Next scientific steps

1. Generate development challenge and representative annotation templates across the 20 development sources.
2. Human-review development gold and materialize approved fixtures.
3. Use development results to choose and justify non-inferiority margins and the bootstrap replicate count.
4. Generate prediction-independent confirmatory templates for the 50 holdout sources and complete blind human annotation/adjudication.
5. Hash the final gold and analysis artifacts into the confirmatory freeze record.
6. Only then run A/B/C on confirmatory sample bundles and produce ADR-0001, ADR-0002, format, degradation, and paired-delta reports.
