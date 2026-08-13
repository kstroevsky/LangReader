#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CORE_ROOT="Sources/LeafReaderCore"
offenders=()

# These suffixes describe ownership of controls, layout, or view formatting.
# The check is intentionally narrower than a dictionary of UI words: domain
# algorithms may validly consume concepts such as a document's printed chrome.
while IFS= read -r path; do
  base="${path##*/}"
  case "$base" in
    *Presenter.swift|*ViewModel.swift|*Presentation.swift|*ToolbarItem.swift|*BottomBarItem.swift|*ChromeState.swift)
      offenders+=("$path")
      ;;
  esac
done < <(find "$CORE_ROOT" -type f -name '*.swift' | LC_ALL=C sort)

if (( ${#offenders[@]} > 0 )); then
  echo "core semantics: FAILED - presentation-owned source is in LeafReaderCore:" >&2
  printf '  %s\n' "${offenders[@]}" >&2
  echo "Move presentation models and control descriptors to LeafReaderApp." >&2
  exit 1
fi

if declarations="$(grep -RInE '^[[:space:]]*(package |public |internal )?(struct|enum|class)[[:space:]]+[A-Za-z0-9_]*(Presenter|ViewModel|Presentation|ToolbarItem|BottomBarItem|ChromeState)([[:space:]:{]|$)' "$CORE_ROOT" --include='*.swift' || true)"; then
  if [[ -n "$declarations" ]]; then
    echo "core semantics: FAILED - Core declares a presentation-owned type:" >&2
    echo "$declarations" >&2
    exit 1
  fi
fi

if [[ -d "$CORE_ROOT/SharedUI" ]] && find "$CORE_ROOT/SharedUI" -type f -name '*.swift' | grep -q .; then
  echo "core semantics: FAILED - SharedUI source is in LeafReaderCore:" >&2
  find "$CORE_ROOT/SharedUI" -type f -name '*.swift' -print >&2
  echo "Move UI source to LeafReaderApp; move domain utilities to an accurately named Core feature or Support directory." >&2
  exit 1
fi

if concepts="$(grep -RInE '(accessibilityIdentifier|accessibilityLabel|UIAccessibilityIdentifiers)|window coordinates' "$CORE_ROOT" --include='*.swift' || true)"; then
  if [[ -n "$concepts" ]]; then
    echo "core semantics: FAILED - Core source owns accessibility or window-presentation concepts:" >&2
    echo "$concepts" >&2
    exit 1
  fi
fi

echo "core semantics: ok - no presentation ownership detected in LeafReaderCore"
