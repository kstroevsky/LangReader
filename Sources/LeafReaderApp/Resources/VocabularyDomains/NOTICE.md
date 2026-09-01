# Experimental vocabulary-domain frequency resources

These compact SQLite rank tables are developer-gated experimental resources.
Production vocabulary difficulty continues to use the general English ECDICT
or German Leipzig News prior until held-out real-learner gates pass.

## Google Books Ngram 2020

Source index: `https://storage.googleapis.com/books/ngrams/books/datasetsv3.html`

Google Books Ngram data is offered under Creative Commons Attribution 3.0
Unported. Attribution: Google Books Ngram Viewer.

### English Fiction

- Resource: `eng_fiction_20200217.sqlite`
- Source version: `20200217`
- Source URL:
  `https://storage.googleapis.com/books/ngrams/books/20200217/eng-fiction/1-00000-of-00001.gz`
- Source MD5: `d4b8b7b0654313359da3eef00c48aafd`
- Derived SHA-256:
  `ab4b82e15194ac77db1beeac806c829c6aad08871202882065c9180883315b88`
- Rows: 200,000

### German

- Resource: `ger_20200217.sqlite`
- Source version: `20200217`
- Source shards: `1-00000-of-00008.gz` through `1-00007-of-00008.gz`
- Ordered URL/MD5 manifest SHA-256:
  `3a55a2dff3e47faaac9c415741426365caf5f4facb807de06bb533515b34998f`
- Derived SHA-256:
  `bf2538cc2bc6952fd8a68bf51d54993b43bcdf3e83b2bf55a0ea882680d3db40`
- Rows: 200,000

Ordered German shard MD5 values:

```text
66e38f0bf9209090713d88e5b2620851
ca71ee7f1a7bddae6fd51965048ce66f
41dc2ea9d4b6c53310d1cf12c9a4f030
bff04041832b558630d1d6a915fab019
20ca66e02b0d89612dd1ab8897edeb12
faa3b2fc44d19a58606caa39ef9d2c83
ff69ad3e560c393282c27a01c9ebbb96
64463f4bdfec6559c1651ccdb4eb212b
```

The deterministic builder verifies every shard, removes supported Google POS
suffixes, aggregates equal case-folded forms across every shard, rejects invalid
word forms, ranks by summed match count with lexical tie-breaking, and requires
exactly 200,000 rows before writing SQLite.

Rebuild both pinned resources with:

```sh
LEAFREADER_GOOGLE_BOOKS_CACHE_DIR=/absolute/cache \
LEAFREADER_GOOGLE_BOOKS_WORKERS=2 \
  ./scripts/build_pinned_google_books_domain_resources.sh
```

## Leipzig Corpora Collection

The English News 2025, English Wikipedia 2016, and German Wikipedia 2021 tables
are derived from the named Leipzig Corpora Collection downloadable corpora.
The German News 2025 table is shared with the production German general prior.

Attribution: © Universität Leipzig, Leipzig Corpora Collection. Downloadable
corpora are made available under CC BY. Exact source and derived checksums are
stored in `VocabularyDocumentDomain.swift`; the production German News notice
is in `../GermanFrequency/NOTICE.md`.

The SQLite tables contain only normalized word keys and rank integers. They do
not contain document text or learner data.
