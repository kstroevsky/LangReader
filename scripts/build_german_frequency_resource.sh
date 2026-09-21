#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <deu_news_2025_1M.tar.gz> <output.sqlite>" >&2
  exit 2
fi

archive_path="$1"
output_path="$2"
expected_sha256="2c55dbe53158bb06c323bfa30407972c219c70a643bbad50cc6b08221fa34e7a"
corpus_member="deu_news_2025_1M/deu_news_2025_1M-words.txt"

if [[ ! -f "$archive_path" ]]; then
  echo "missing corpus archive: $archive_path" >&2
  exit 1
fi

actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "corpus checksum mismatch: expected $expected_sha256, got $actual_sha256" >&2
  exit 1
fi

temporary_root="$(mktemp -d /tmp/leafreader-german-rank.XXXXXX)"
trap 'rm -rf "$temporary_root"' EXIT
ranked_tsv="$temporary_root/ranked.tsv"
import_tsv="$temporary_root/import.tsv"

tar -xOzf "$archive_path" "$corpus_member" \
  | perl -CSDA -Mutf8 -ne '
      chomp;
      my ($id, $word, $frequency) = split(/\t/, $_, 3);
      next unless defined($frequency) && $frequency =~ /^\d+$/;
      next unless $word =~ /^\p{L}[\p{L}\p{M}\x{27}\x{2019}-]*$/;
      next if length($word) > 64;
      print "$frequency\t", lc($word), "\n";
    ' \
  | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 \
  > "$ranked_tsv"

awk -F $'\t' '
  BEGIN { rank = 0 }
  !seen[$2]++ {
    rank += 1
    print $2 "\t" rank
    if (rank == 200000) exit
  }
' "$ranked_tsv" > "$import_tsv"

row_count="$(wc -l < "$import_tsv" | tr -d ' ')"
if [[ "$row_count" != "200000" ]]; then
  echo "expected 200000 ranked forms, got $row_count" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
sqlite3 "$output_path" <<SQL
PRAGMA journal_mode=OFF;
PRAGMA synchronous=OFF;
CREATE TABLE word_rank (word_key TEXT PRIMARY KEY, rank INTEGER NOT NULL) WITHOUT ROWID;
.mode tabs
.import '$import_tsv' word_rank
CREATE UNIQUE INDEX word_rank_rank ON word_rank(rank);
VACUUM;
SQL

echo "created $output_path ($row_count rows)"
shasum -a 256 "$output_path"
