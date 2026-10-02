# Representative-book development corpus v1

## Status

This is development-only evidence for the ADR-0001/ADR-0002 representative-book program. It is not held-out or release-gating evidence, and anything inspected here remains permanently unavailable as a fresh confirmatory source.

The canonical role assignment and source hashes live in `representative-book-corpus-manifest-v1.json`. The current large-corpus development role contains **20 documents / 18 work families**. The count is lower than the document count because the Patrick Radden Keefe and Saša Stanišić cross-cohort translation pairs are explicitly clustered as the same underlying works:

| Dimension | Development coverage |
| --- | --- |
| Language | 12 English, 8 German |
| Format | 10 PDF, 10 EPUB |
| Genre | 12 literary fiction, 2 biography/memoir, 2 popular non-fiction, 2 non-fiction, 2 reference |

The role split was made from source/cohort structure before checkpoint predictions. Work/translation families may not cross from development into confirmatory evidence.

## Panels

Every development source may produce two distinct panels:

- `representative-book-challenge-v3`: development-only failure finding. NaturalLanguage lemma/POS output may prioritize suspicious anchors.
- `representative-book-representative-v2`: prediction-independent source-position/canonical-surface sampling used to estimate ordinary-book behavior.

PDF v3/v2 sampling operates across readable PDFKit pages and preserves original page numbers in provenance. EPUB uses deterministic `epub-paragraph-pack-v1` units extracted through the production `WebDocumentLoader`.

Annotation templates contain book context and therefore remain local/private. Safe metadata, source hashes, policy versions, and aggregate reports may be stored in the repository.

## Historical Martin Eden diagnostics

The earlier `martin-eden-en` and `martin-eden-de` artifacts remain valid **historical development diagnostics** under `representative-book-candidate-v1`. Their metadata is intentionally not relabeled to the newer policies:

- `martin-eden-en-development-metadata-v1.json`
- `martin-eden-de-development-metadata-v1.json`

Those documents/predictions have already been inspected, so neither they nor other pages from the same works can become fresh holdout evidence. The schema-v1 materializer path remains supported for this historical evidence.

## Review and materialization policy

Human annotation is authoritative. NaturalLanguage output must not be copied into `goldLemma` or `goldPartOfSpeech` as truth. Approved rows are aligned back to the exact source hash, sampled-text hash, sampled unit, UTF-16 range, and surface before a reconciler-conditional fixture can be emitted.

Schema-v2 PDF/EPUB annotations use the same production extraction policy for generation, sample-bundle construction, and materialization. A provenance mismatch is an error; ranges are never manually moved to make an annotation fit.

## Current boundary

The 20-source role/corpus freeze and executable tooling are ready, but broad development human gold has not been frozen. Development challenge/representative templates may be generated and reviewed iteratively. Confirmatory A/B/C execution remains separately blocked until the 50-source holdout has blind human gold, numeric non-inferiority margins, bootstrap count, missing-data/enrollment/retry rules, and the final confirmatory freeze record.

DOCX controlled parity, deliberate NLP degradation, assessment-path consequences, and unsupported-language routing remain separate required experiment strata; they are not inferred from the natural PDF/EPUB book sample.
