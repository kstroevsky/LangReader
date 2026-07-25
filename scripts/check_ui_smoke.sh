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

on walkChrome(el, depth, wanted, mode)
    set acc to ""
    if depth > 10 then return acc
    tell application "System Events"
        set kids to {}
        try
            set kids to UI elements of el
        end try
        repeat with e in kids
            set r to ""
            try
                set r to (role of e) as string
            end try
            -- Skip the PDF/web scroll areas: that subtree is enormous.
            if r is not "AXScrollArea" then
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
                set r2 to my walkChrome(e, depth + 1, wanted, mode)
                if mode is "click" and r2 is "CLICKED" then return "CLICKED"
                set acc to acc & r2
            end if
        end repeat
    end tell
    return acc
end walkChrome
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

# Walks one window by name, whatever its subrole. Needed for screens that live
# in a real titled window (the Words library) rather than a borderless panel —
# `panel_identifiers` skips those to avoid the reader window's PDF tree.
named_window_identifiers() {
  activate_app
  run_as '    set out to ""
    tell application "System Events" to tell process "'"$APP_NAME"'"
        repeat with i from 1 to (count of windows)
            if (name of window i) as string is "'"$1"'" then
                set out to out & my walk(window i, 1, "", "list")
            end if
        end repeat
    end tell
    return out'
}

# The library's summary reads "13 of 13 words". Used to decide whether rows are
# required: with words saved, an empty list is a regression; with none, it is
# simply an empty library.
library_word_count() {
  activate_app
  osascript -e "with timeout of 20 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  repeat with i from 1 to (count of windows)
    if (name of window i) as string is \"Words\" then
      repeat with t in (static texts of window i)
        try
          set v to (value of t) as string
          -- Must start with a digit: AppleScript's \"contains\" is
          -- case-insensitive, so matching on the word \"words\" also matched
          -- the window's own \"Words\" title and parsed no count from it.
          if v is not \"\" and (character 1 of v) is in \"0123456789\" then return v
        end try
      end repeat
    end if
  end repeat
end tell
return \"\"
end timeout" 2>&1
}

window_exists() {
  activate_app
  osascript -e "with timeout of 20 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  repeat with i from 1 to (count of windows)
    if (name of window i) as string is \"$1\" then return \"YES\"
  end repeat
end tell
return \"NO\"
end timeout" 2>&1
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

reader_chrome_identifiers() {
  activate_app
  run_as '    tell application "System Events" to tell process "'"$APP_NAME"'"
        return my walkChrome(first window whose subrole is "AXStandardWindow", 1, "", "list")
    end tell'
}

click_reader_chrome() {
  activate_app
  run_as '    tell application "System Events" to tell process "'"$APP_NAME"'"
        return my walkChrome(first window whose subrole is "AXStandardWindow", 1, "'"$1"'", "click")
    end tell'
}

main_button_identifiers() {
  activate_app
  osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  set out to \"\"
  repeat with b in (buttons of (first window whose subrole is \"AXStandardWindow\"))
    try
      set aid to (value of attribute \"AXIdentifier\" of b)
      if aid is not missing value and aid is not \"\" then set out to out & aid & linefeed
    end try
  end repeat
  return out
end tell
end timeout" 2>&1
}

# Clicks a direct main-window button by accessibility identifier. Locale-proof,
# and survives the bar's eventual move to SwiftUI, where titles disappear.
click_main_identifier() {
  activate_app
  osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  repeat with b in (buttons of (first window whose subrole is \"AXStandardWindow\"))
    try
      if (value of attribute \"AXIdentifier\" of b) is \"$1\" then
        click b
        return \"CLICKED\"
      end if
    end try
  end repeat
end tell
return \"NOTFOUND\"
end timeout" >/dev/null 2>&1
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

echo "reader chrome"
# Both bars are asserted by accessibility identifier rather than by button title:
# titles are localised (a Chinese UI would break a title match), and identifiers
# are stable across the AppKit->SwiftUI migration, making this a regression net.
CHROME_IDS="$(reader_chrome_identifiers)"
# A failure to read any chrome identifier usually means accessibility permission
# is missing rather than a real regression, so it is called out separately.
if ! grep -q "bottomBar\." <<<"$CHROME_IDS"; then
  echo "UI smoke: cannot read the app's accessibility tree." >&2
  echo "Grant Accessibility permission to this terminal and re-run." >&2
  echo "--- got: ---" >&2
  echo "$CHROME_IDS" >&2
  exit 2
fi
for id in settings shelf words notes review toc cover previousPage nextPage farthestPosition; do
  expect_identifier "bottomBar.$id" "$CHROME_IDS" "bottom bar $id"
done
# The top toolbar is SwiftUI now; assert its controls by identifier too. The
# restored PDF session shows read-aloud, page-layout, crop and full-screen.
for id in readAloud pageLayout crop fullScreen; do
  expect_identifier "topBar.$id" "$CHROME_IDS" "top bar $id"
done
# The AI panel's chrome (header actions + status row) is SwiftUI too. Its
# identifiers are readable whether the panel is expanded or collapsed, so
# asserting them needs no state change and leaves the panel as the user left it.
for id in ask summarize translate export; do
  expect_identifier "aiPanel.$id" "$CHROME_IDS" "AI panel $id"
done

echo "reading notes (SwiftUI)"
click_reader_chrome "bottomBar.notes"
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

echo "model settings (SwiftUI)"
activate_app
osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\" to click menu item \"Model\" of menu 1 of menu bar item \"Settings\" of menu bar 1
end timeout" >/dev/null 2>&1
sleep 3
MODEL_IDS="$(panel_identifiers)"
expect_identifier "settings.model.picker"   "$MODEL_IDS" "model picker"
expect_identifier "settings.model.apiKey"   "$MODEL_IDS" "API key field"
expect_identifier "settings.model.testChat" "$MODEL_IDS" "test chat button"


echo "AI analysis settings (SwiftUI)"
activate_app
osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\" to click menu item \"AI Analysis\" of menu 1 of menu bar item \"Settings\" of menu bar 1
end timeout" >/dev/null 2>&1
sleep 3
EMBED_IDS="$(panel_identifiers)"
expect_identifier "settings.embedding.picker"    "$EMBED_IDS" "embedding provider picker"
expect_identifier "settings.embedding.apiKey"    "$EMBED_IDS" "embedding key field"
expect_identifier "settings.embedding.autoIndex" "$EMBED_IDS" "auto-index toggle"

# Cancel, never Save: the smoke test must not write the user's settings.
[[ "$(click_panel_button_titled "Cancel")" == *CLICKED* ]] && pass "settings cancels" || fail "settings would not cancel"
sleep 2

echo "vocabulary library (SwiftUI list)"
click_reader_chrome "bottomBar.words"
sleep 5
# Assert the window opened. Rows alone are not enough to assert on: a library
# with no saved words legitimately has none, so a broken list and an empty one
# would look identical and a real regression would pass silently.
if [[ "$(window_exists "Words")" == *YES* ]]; then
  pass "library window opens"
else
  fail "library window did not open"
fi
LIBRARY_IDS="$(named_window_identifiers "Words")"
LIBRARY_SUMMARY="$(library_word_count)"
# Leading integer of "13 of 13 words"; empty/unparsed counts as zero.
LIBRARY_WORDS="$(sed -n 's/^\([0-9][0-9]*\).*/\1/p' <<<"$LIBRARY_SUMMARY" | head -1)"
LIBRARY_WORDS="${LIBRARY_WORDS:-0}"
if grep -qx "vocabulary.row" <<<"$LIBRARY_IDS"; then
  pass "library list renders word rows (vocabulary.row)"
elif (( LIBRARY_WORDS > 0 )); then
  fail "library reports $LIBRARY_WORDS words but rendered no rows"
else
  echo "  --   library is empty; row rendering not covered this run"
fi
activate_app
osascript -e "with timeout of 30 seconds
tell application \"System Events\" to tell process \"$APP_NAME\"
  try
    click (first button of (first window whose name is \"Words\") whose subrole is \"AXCloseButton\")
  end try
end tell
end timeout" >/dev/null 2>&1
sleep 2

echo "shelf (SwiftUI)"
click_reader_chrome "bottomBar.shelf"
sleep 4
SHELF_IDS="$(panel_identifiers)"
expect_identifier "shelf.add"   "$SHELF_IDS" "add button"
expect_identifier "shelf.clear" "$SHELF_IDS" "clear button"
expect_identifier "shelf.close" "$SHELF_IDS" "close button"
# Card presence is reported, not asserted: a user with no recent documents has
# an empty shelf, which is correct rather than broken.
if grep -qx "shelf.card" <<<"$SHELF_IDS"; then
  pass "shelf shows at least one document card"
else
  echo "  --   no shelf cards (empty recents); card rendering not covered this run"
fi
[[ "$(click_identifier shelf.close)" == *CLICKED* ]] && pass "shelf closes" || fail "shelf would not close"
sleep 2

echo
if (( FAILURES > 0 )); then
  echo "UI smoke: $FAILURES of $CHECKS checks failed."
  exit 1
fi
echo "UI smoke: all $CHECKS checks passed."
