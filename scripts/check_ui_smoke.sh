#!/bin/bash
# Drives the built app through its migrated SwiftUI screens and asserts that the
# controls are present and addressable.
#
# This is the only automated coverage those screens have. Unit tests cover the
# presenters behind them; nothing else checks that the screens actually build,
# open, and expose their controls — a SwiftUI view that fails to lay out, or a
# hosting view that never gets attached, still compiles and still passes every
# logic test.
#
# It asserts on accessibility identifiers (see UIAccessibilityIdentifiers.swift)
# rather than on screen positions, so it doubles as a check that the screens
# remain usable with assistive technology.
#
# The app is launched and quit by this script. It only opens panels and
# dismisses them with Cancel/Close — it never clicks a destructive control, so
# it is safe to run against a real library.
#
# Requires accessibility permission for the terminal running it
# (System Settings > Privacy & Security > Accessibility).

set -uo pipefail

APP_NAME="Leaf Vocabulary"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${LEAFVOCAB_APP_PATH:-$REPO_ROOT/$APP_NAME.app}"

FAILURES=0
CHECKS=0

pass() { CHECKS=$((CHECKS + 1)); printf '  ok   %s\n' "$1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); printf '  FAIL %s\n' "$1"; }

if [[ ! -d "$APP_PATH" ]]; then
  echo "UI smoke: no app bundle at $APP_PATH" >&2
  echo "Build it first: ./scripts/build_app.sh --debug" >&2
  exit 2
fi

# --- AppleScript helpers -----------------------------------------------------

# Every screen under test is its own panel window. The main reader window is
# skipped on purpose: it hosts the PDF/web view, whose accessibility tree is
# large enough that walking it takes minutes.
read -r -d '' AS_PREAMBLE <<'APPLESCRIPT'
-- The `tell application "System Events"` wrapper is load-bearing: reading an
-- accessibility attribute outside it leaves the reference unresolvable and the
-- call blocks indefinitely rather than failing.
on isPanel(w)
    set sub to ""
    tell application "System Events"
        try
            set sub to (subrole of w) as string
        end try
    end tell
    return sub is not "AXStandardWindow"
end isPanel

on walk(el, depth, wanted, mode)
    set acc to ""
    if depth > 8 then return acc
    tell application "System Events"
        set kids to {}
        try
            set kids to UI elements of el
        end try
        repeat with e in kids
            try
                set theID to value of attribute "AXIdentifier" of e
                if theID is not missing value and theID is not "" then
                    if mode is "list" then
                        set acc to acc & theID & linefeed
                    else if theID is wanted then
                        click e
                        return "CLICKED"
                    end if
                end if
            end try
            set r to my walk(e, depth + 1, wanted, mode)
            if mode is "click" and r is "CLICKED" then return "CLICKED"
            set acc to acc & r
        end repeat
    end tell
    return acc
end walk
APPLESCRIPT

run_as() {
  osascript <<APPLESCRIPT 2>&1
$AS_PREAMBLE

on run
$1
end run
APPLESCRIPT
}

activate_app() {
  osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1
  sleep 2
}

# Prints one identifier per line for every panel window.
panel_identifiers() {
  activate_app
  run_as '    set out to ""
    tell application "System Events" to tell process "'"$APP_NAME"'"
        repeat with i from 1 to (count of windows)
            if my isPanel(window i) then set out to out & my walk(window i, 1, "", "list")
        end repeat
    end tell
    return out'
}

click_identifier() {
  activate_app
  run_as '    tell application "System Events" to tell process "'"$APP_NAME"'"
        repeat with i from 1 to (count of windows)
            if my isPanel(window i) then
                if (my walk(window i, 1, "'"$1"'", "click")) is "CLICKED" then return "CLICKED"
            end if
        end repeat
    end tell
    return "NOTFOUND"'
}

# Main-window controls are plain AppKit buttons with titles.
click_main_button() {
  activate_app
  osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\" to click (first button of (first window whose subrole is \"AXStandardWindow\") whose title is \"$1\")
end timeout" >/dev/null 2>&1
}

click_panel_button_titled() {
  activate_app
  osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  repeat with i from 1 to (count of windows)
    if (subrole of window i) as string is not \"AXStandardWindow\" then
      try
        click (first button of window i whose title is \"$1\")
        return \"CLICKED\"
      end try
    end if
  end repeat
end tell
return \"NOTFOUND\"
end timeout" 2>&1
}

main_button_titles() {
  activate_app
  osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  set out to \"\"
  repeat with b in (buttons of (first window whose subrole is \"AXStandardWindow\"))
    try
      if (title of b) is not \"\" then set out to out & (title of b) & linefeed
    end try
  end repeat
  return out
end tell
end timeout" 2>&1
}

expect_identifier() {
  local id="$1" haystack="$2" label="$3"
  if grep -qx "$id" <<<"$haystack"; then pass "$label ($id)"; else fail "$label — missing $id"; fi
}

# --- Lifecycle ---------------------------------------------------------------

quit_app() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1
  sleep 2
  pkill -f "$APP_NAME" >/dev/null 2>&1
  sleep 1
}

cleanup() { quit_app; }
trap cleanup EXIT

echo "UI smoke: $APP_PATH"
quit_app
open "$APP_PATH" || { echo "UI smoke: could not launch app" >&2; exit 2; }
sleep 9
activate_app

if ! pgrep -f "$APP_NAME" >/dev/null; then
  echo "UI smoke: app did not stay running" >&2
  exit 2
fi

# A failure here usually means accessibility permission is missing rather than a
# real regression, so it is called out separately.
TITLES="$(main_button_titles)"
if ! grep -q "Notes" <<<"$TITLES"; then
  echo "UI smoke: cannot read the app's accessibility tree." >&2
  echo "Grant Accessibility permission to this terminal and re-run." >&2
  echo "--- got: ---" >&2
  echo "$TITLES" >&2
  exit 2
fi

echo "reader chrome"
for title in Shelf Words Notes Review TOC Cover Prev Next Last Read; do
  if grep -qx "$title" <<<"$TITLES"; then pass "toolbar button $title"; else fail "toolbar button $title missing"; fi
done

echo "reading notes (SwiftUI)"
click_main_button "Notes"
sleep 3
NOTES_IDS="$(panel_identifiers)"
expect_identifier "notes.search"  "$NOTES_IDS" "search field"
expect_identifier "notes.summary" "$NOTES_IDS" "summary label"
expect_identifier "notes.export"  "$NOTES_IDS" "export button"
expect_identifier "notes.close"   "$NOTES_IDS" "close button"
[[ "$(click_identifier notes.close)" == *CLICKED* ]] && pass "notes panel closes" || fail "notes panel would not close"
sleep 2

echo "general settings (SwiftUI)"
activate_app
osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\" to click menu item \"General\" of menu 1 of menu bar item \"Settings\" of menu bar 1
end timeout" >/dev/null 2>&1
sleep 3
SETTINGS_IDS="$(panel_identifiers)"
expect_identifier "settings.general.language"        "$SETTINGS_IDS" "language picker"
expect_identifier "settings.general.theme"           "$SETTINGS_IDS" "theme picker"
expect_identifier "settings.general.speakWord"       "$SETTINGS_IDS" "auto-play toggle"
expect_identifier "settings.general.saveConversation" "$SETTINGS_IDS" "save-conversation toggle"
# Cancel, never Save: the smoke test must not write the user's settings.
[[ "$(click_panel_button_titled "Cancel")" == *CLICKED* ]] && pass "settings cancels" || fail "settings would not cancel"
sleep 2

echo "shelf (AppKit)"
click_main_button "Shelf"
sleep 4
SHELF_TITLES="$(activate_app; osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  set out to \"\"
  repeat with i from 1 to (count of windows)
    if (subrole of window i) as string is not \"AXStandardWindow\" then
      repeat with b in (buttons of window i)
        try
          if (title of b) is not \"\" then set out to out & (title of b) & linefeed
        end try
      end repeat
    end if
  end repeat
  return out
end tell
end timeout" 2>&1)"
# Presence only — "Clear" wipes the recents list and is never clicked.
for title in Add Clear; do
  if grep -qx "$title" <<<"$SHELF_TITLES"; then pass "shelf button $title"; else fail "shelf button $title missing"; fi
done
activate_app
osascript -e "tell application \"System Events\" to key code 53" >/dev/null 2>&1
sleep 2

echo
if (( FAILURES > 0 )); then
  echo "UI smoke: $FAILURES of $CHECKS checks failed."
  exit 1
fi
echo "UI smoke: all $CHECKS checks passed."
