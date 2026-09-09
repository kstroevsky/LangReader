# Vocabulary Preparation Cross Format Fixtures

This supplement contains one authored English text and one authored German text,
each rendered as PDF, EPUB, and DOCX. The six files are two content-equivalence
groups, not six independent study documents. They exercise repeated homographs,
inflected and participial forms, visual line wrapping, compounds, Unicode,
apostrophes, and hyphens without private source material or network access.

The committed artifacts were generated with the pinned CPython 3.12.14
standard-library pipeline recorded in `manifest.json`:

```sh
python3 scripts/generate_vocabulary_preparation_fixtures.py
python3 scripts/generate_vocabulary_preparation_fixtures.py --check
```

`manifest.json` records source and artifact SHA-256 values, byte counts, and the
complete case-normalized surface-token inventory for each source. Regeneration
uses fixed ZIP timestamps and a deterministic minimal PDF writer. Review changes
to a source, its complete inventory, and all three representations together.

These fixtures supplement but do not replace the private English/German
PDF/EPUB/DOCX performance manifest required for the real-app matrix. The source
and generated artifacts are licensed under CC0 1.0; see `LICENSE.md`.
