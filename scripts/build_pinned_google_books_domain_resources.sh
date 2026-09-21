#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/Sources/LeafReaderApp/Resources/VocabularyDomains}"
BUILDER="$ROOT_DIR/scripts/build_google_books_domain_resource.sh"
mkdir -p "$OUTPUT_DIR"

"$BUILDER" "$OUTPUT_DIR/eng_fiction_20200217.sqlite" 200000 \
  https://storage.googleapis.com/books/ngrams/books/20200217/eng-fiction/1-00000-of-00001.gz \
  d4b8b7b0654313359da3eef00c48aafd

"$BUILDER" "$OUTPUT_DIR/ger_20200217.sqlite" 200000 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00000-of-00008.gz \
  66e38f0bf9209090713d88e5b2620851 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00001-of-00008.gz \
  ca71ee7f1a7bddae6fd51965048ce66f \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00002-of-00008.gz \
  41dc2ea9d4b6c53310d1cf12c9a4f030 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00003-of-00008.gz \
  bff04041832b558630d1d6a915fab019 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00004-of-00008.gz \
  20ca66e02b0d89612dd1ab8897edeb12 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00005-of-00008.gz \
  faa3b2fc44d19a58606caa39ef9d2c83 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00006-of-00008.gz \
  ff69ad3e560c393282c27a01c9ebbb96 \
  https://storage.googleapis.com/books/ngrams/books/20200217/ger/1-00007-of-00008.gz \
  64463f4bdfec6559c1651ccdb4eb212b
