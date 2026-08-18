#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: $0 <output.sqlite> <rows> <url> <expected-md5> [<url> <expected-md5> ...]" >&2
  exit 2
fi
if (( ($# - 2) % 2 != 0 )); then
  echo "every Google Books URL needs a pinned MD5" >&2
  exit 2
fi

output_path="$1"
expected_rows="$2"
shift 2
temporary_root="$(mktemp -d /tmp/leafreader-google-books-rank.XXXXXX)"
trap 'rm -rf "$temporary_root"' EXIT
candidates_tsv="$temporary_root/candidates.tsv"
import_tsv="$temporary_root/import.tsv"
: > "$candidates_tsv"

shard=0
while (( $# > 0 )); do
  url="$1"
  expected_md5="$2"
  shift 2
  archive="$temporary_root/shard-$shard.gz"
  shard_ranked="$temporary_root/shard-$shard.tsv"
  curl -L --fail --silent --show-error --output "$archive" "$url"
  actual_md5="$(md5 -q "$archive")"
  if [[ "$actual_md5" != "$expected_md5" ]]; then
    echo "Google Books shard checksum mismatch: expected $expected_md5, got $actual_md5" >&2
    exit 1
  fi
  gzip -dc "$archive" | perl -CSDA -Mutf8 -ne '
    chomp;
    my @fields = split(/\t/, $_);
    my $word = shift @fields;
    next unless $word =~ /^\p{L}[\p{L}\p{M}\x{27}\x{2019}-]*$/;
    next if length($word) > 64;
    my $frequency = 0;
    for my $year (@fields) {
      my (undef, $matches) = split(/,/, $year, 3);
      $frequency += $matches if defined($matches) && $matches =~ /^\d+$/;
    }
    print "$frequency\t", lc($word), "\n" if $frequency > 0;
  ' | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 \
    | awk -F $'\t' -v expected_rows="$expected_rows" '
        NR <= expected_rows { print }
      ' > "$shard_ranked"
  cat "$shard_ranked" >> "$candidates_tsv"
  rm -f "$archive"
  shard=$((shard + 1))
done

LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 "$candidates_tsv" \
  | awk -F $'\t' -v expected_rows="$expected_rows" '
      BEGIN { rank = 0 }
      !seen[$2]++ {
        rank += 1
        print $2 "\t" rank
        if (rank == expected_rows) exit
      }
    ' > "$import_tsv"

row_count="$(wc -l < "$import_tsv" | tr -d ' ')"
if [[ "$row_count" != "$expected_rows" ]]; then
  echo "expected $expected_rows ranked forms, got $row_count" >&2
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
