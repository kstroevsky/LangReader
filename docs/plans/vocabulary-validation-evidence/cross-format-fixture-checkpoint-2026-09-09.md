# Cross format fixture checkpoint — 2026-09-09

## Status

The redistributable supplemental English/German PDF, EPUB, and DOCX fixture set
is implemented, reproducible, visually reviewed, and covered by deterministic
extraction tests. It supplements but does not replace the required private
six-document real-app matrix.

## Fixture design and provenance

Both source texts were authored for this repository and dedicated under CC0
1.0. Each begins with a descriptive title and scope paragraph, then includes
ordinary prose, repeated occurrence weights, homographs, noun/verb ambiguity,
inflected and participial forms, visual line wrapping, Unicode accents and
umlauts, apostrophes, hyphens, and compounds.

The English source contains 374 case-normalized surface tokens and 285 unique
tokens. The German source contains 335 surface tokens and 264 unique tokens.
Each source is rendered into PDF, EPUB, and DOCX, producing two
content-equivalence groups rather than six independent documents.

`Tests/Fixtures/VocabularyPreparation/manifest.json` records:

- the fixture-set and generator schema versions;
- the exact CPython 3.12.14 standard-library generation environment;
- source and artifact SHA-256 values;
- artifact byte counts;
- the complete expected surface-token inventory and occurrence count for each
  language.

The generator fixes ZIP member timestamps and writes PDF objects and cross
references deterministically. Its `--check` mode rebuilds into an isolated
temporary directory and rejects any byte-level drift. This check is wired into
`scripts/check.sh`.

## Verification evidence

- A clean generation followed by `--check` reproduced all six committed
  artifacts byte for byte.
- `VocabularyPreparationFixtureXCTests` verify the
  manifest shape, all source/artifact hashes and byte counts, then extract each
  PDF with PDFKit and each EPUB/DOCX through the production Web document loader.
  Every format reproduced its language's complete expected inventory exactly.
- A later pipeline-parity extension runs all six extracted documents through
  the real NaturalLanguage lemma/POS index, unknown-POS reconciliation,
  production difficulty provider, final inventory filter/order, and eight fixed
  cold answers. PDF, EPUB, and DOCX must match exactly for candidate identity,
  occurrence mass, exclusions, difficulty source/version/rank, ordering, and
  first-question identities within the executing macOS runtime. Core tags an
  equal-length whitespace-normalized view so renderer line wrapping cannot
  change linguistic context while source/highlight ranges remain unchanged.
- `unzip -t` passed for both EPUB and both DOCX packages.
- Both DOCX files were rendered with the bundled LibreOffice pipeline and every
  resulting page was visually inspected. Both are clean, readable one-page
  Letter documents with no clipping, overlap, missing glyphs, or broken spacing.
- Both PDFs report one Letter page, are parsed by PDFKit in the extraction test,
  and every page was rasterized with the bundled PDFium fallback and visually
  inspected. The first direct bundled Poppler rasterization stalled on this
  host, so it was terminated; no fixture or product process remained running.
- `./scripts/check.sh --no-build` passed with the regeneration check wired in;
  this included 167 Swift tests (one intentional skip), the regression harness,
  281 logic tests, capture validators, and all vocabulary evaluator/self-test
  stages.

## Remaining external evidence

The supplemental fixtures are development controls. No real-app performance
values or release acceptance are inferred from them. The private representative
English/German PDF/EPUB/DOCX manifest is still absent, so the required private
GUI matrix, same-machine document-open controls, cold/warm repetitions, and raw
usable-question latency distributions remain awaiting external fixtures.

## Next action

Use the existing `vocabulary-preparation-fixtures.example.json`,
`vocabulary_preparation_fixture_manifest.py`, and
`check_vocabulary_preparation_smoke.sh` workflow when the private documents are
available. Retain supplemental and private results as different evidence
classes and preserve unfavorable repetitions.
