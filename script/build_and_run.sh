#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Leaf Vocabulary"
BUNDLE_ID="dev.wordslist.leafvocabulary"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
SPARKLE_HOME="${SPARKLE_HOME:-/opt/homebrew/Caskroom/sparkle/2.9.2}"

if [[ ! -d "$SPARKLE_HOME/Sparkle.framework" && -d "/Applications/Leaf Reader.app/Contents/Frameworks/Sparkle.framework" ]]; then
  SPARKLE_HOME="/Applications/Leaf Reader.app/Contents/Frameworks"
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
SPARKLE_HOME="$SPARKLE_HOME" "$ROOT_DIR/scripts/build_app.sh" --debug --arm64

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
