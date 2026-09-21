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
aggregated_tsv="$temporary_root/aggregated.tsv"
import_tsv="$temporary_root/import.tsv"
download_root="${LEAFREADER_GOOGLE_BOOKS_CACHE_DIR:-$temporary_root/downloads}"
transform_version="valid-forms-v2"
worker_limit="${LEAFREADER_GOOGLE_BOOKS_WORKERS:-2}"
if ! [[ "$worker_limit" =~ ^[1-9][0-9]*$ ]]; then
  echo "LEAFREADER_GOOGLE_BOOKS_WORKERS must be a positive integer" >&2
  exit 2
fi
mkdir -p "$download_root"

declare -a urls=()
declare -a expected_md5s=()
while (( $# > 0 )); do
  urls+=("$1")
  expected_md5s+=("$2")
  shift 2
done

process_shard() {
  local shard="$1"
  local url="$2"
  local expected_md5="$3"
  local archive="$download_root/$expected_md5.gz"
  local partial="$archive.partial.$$"
  local shard_ranked="$temporary_root/shard-$shard.tsv"
  local processed="$download_root/$expected_md5.$transform_version.tsv"
  local processed_partial="$processed.partial.$$"
  local actual_md5
  if [[ ! -f "$archive" ]]; then
    curl -L --fail --silent --show-error --output "$partial" "$url"
    mv "$partial" "$archive"
  fi
  actual_md5="$(md5 -q "$archive")"
  if [[ "$actual_md5" != "$expected_md5" ]]; then
    echo "Google Books shard checksum mismatch: expected $expected_md5, got $actual_md5" >&2
    return 1
  fi
  if [[ -f "$processed" ]]; then
    cp "$processed" "$shard_ranked"
    return 0
  fi
  gzip -dc "$archive" | perl -CSDA -Mutf8 -ne '
    chomp;
    my $tab = index($_, "\t");
    next if $tab < 1;
    my $word = substr($_, 0, $tab);
    $word =~ s/_(?:NOUN|VERB|ADJ|ADV|PRON|DET|ADP|NUM|CONJ|PRT|X)$//;
    next unless $word =~ /^\p{L}[\p{L}\p{M}\x{27}\x{2019}-]*$/;
    next if length($word) > 64;
    my $frequency = 0;
    while ($_ =~ /\t\d+,(\d+),\d+/g) {
      $frequency += $1;
    }
    print lc($word), "\t$frequency\n" if $frequency > 0;
  ' | LC_ALL=C sort -t $'\t' -k1,1 \
    | awk -F $'\t' '
        NR == 1 { word = $1; frequency = $2; next }
        $1 == word { frequency += $2; next }
        { print frequency "\t" word; word = $1; frequency = $2 }
        END { if (NR > 0) print frequency "\t" word }
      ' > "$processed_partial"
  mv "$processed_partial" "$processed"
  cp "$processed" "$shard_ranked"
}

batch_pids=""
batch_size=0
wait_for_batch() {
  local worker_exit=0
  local pid
  for pid in $batch_pids; do
    wait "$pid" || worker_exit=1
  done
  batch_pids=""
  batch_size=0
  return "$worker_exit"
}

for shard in "${!urls[@]}"; do
  process_shard "$shard" "${urls[$shard]}" "${expected_md5s[$shard]}" &
  batch_pids="$batch_pids $!"
  batch_size=$((batch_size + 1))
  if (( batch_size >= worker_limit )); then
    wait_for_batch || exit 1
  fi
done
wait_for_batch || exit 1

for shard in "${!urls[@]}"; do
  cat "$temporary_root/shard-$shard.tsv" >> "$candidates_tsv"
done

LC_ALL=C sort -t $'\t' -k2,2 "$candidates_tsv" \
  | awk -F $'\t' '
      NR == 1 { word = $2; frequency = $1; next }
      $2 == word { frequency += $1; next }
      { print frequency "\t" word; word = $2; frequency = $1 }
      END { if (NR > 0) print frequency "\t" word }
    ' > "$aggregated_tsv"

LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 "$aggregated_tsv" \
  | awk -F $'\t' -v expected_rows="$expected_rows" '
      NR <= expected_rows { print $2 "\t" NR }
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
for shard in "${!urls[@]}"; do
  printf '%s\t%s\n' "${urls[$shard]}" "${expected_md5s[$shard]}"
done | shasum -a 256
