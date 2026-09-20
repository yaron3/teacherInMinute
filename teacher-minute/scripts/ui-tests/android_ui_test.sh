#!/usr/bin/env bash
#
# Android UI test: sign in, check the home screen, write a question, use the
# algebra keyboard.
#
# Driven through adb and uiautomator, so it needs nothing installed beyond the
# platform tools and no androidTest source set in the Gradle build. Elements are
# found by their text in the accessibility tree rather than by coordinates, and
# every label is matched in both English and Hebrew, because the app's language
# is an account preference rather than a device setting.
#
# The flow deliberately stops before sending the question. Dispatch fans a
# question out to every online teacher covering its topic, so a test must never
# submit one — see the project's CLAUDE.md.
#
# Usage:
#   ./android_ui_test.sh [--device <serial>] [--skip-login] [--keep-data]
#
#   --skip-login   Start from a device that is already signed in.
#   --keep-data    Do not clear app data first. Without it the script runs
#                  `pm clear`, which SIGNS THE DEVICE OUT — never point the
#                  default at a phone whose session you want to keep.
#   --animations-off
#                  Set the three animation scales to 0 for the run and restore
#                  them afterwards. uiautomator will not dump a screen that
#                  never reaches idle, and the question sheet does not: the
#                  field takes focus on open and its caret blinks forever.
#                  Without this the run stops at the sheet, reporting why.
#
# Credentials come from the environment so they are not required to live here:
#   TIM_TEST_EMAIL     (default s1@a.com)
#   TIM_TEST_PASSWORD  (default 123456)

set -euo pipefail

PACKAGE="com.yaronj.tim"
ACTIVITY="teacher.minute.MainActivity"
EMAIL="${TIM_TEST_EMAIL:-s1@a.com}"
PASSWORD="${TIM_TEST_PASSWORD:-123456}"
DEVICE=""
SKIP_LOGIN=0
KEEP_DATA=0
ANIMATIONS_OFF=0
ARTIFACTS="${TMPDIR:-/tmp}/tim-android-ui-test"
HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui_query.py"
DUMP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --skip-login) SKIP_LOGIN=1; shift ;;
    --keep-data) KEEP_DATA=1; shift ;;
    --animations-off) ANIMATIONS_OFF=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi
[[ -n "$DEVICE" ]] || { echo "no adb device found"; exit 1; }

ADB=(adb -s "$DEVICE")
mkdir -p "$ARTIFACTS"
DUMP="$ARTIFACTS/ui.xml"
[[ -f "$HELPER" ]] || { echo "missing helper: $HELPER"; exit 1; }
FAILURES=0
STEP=0

log()  { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

shot() {
  STEP=$((STEP + 1))
  "${ADB[@]}" exec-out screencap -p > "$ARTIFACTS/$(printf '%02d' $STEP)-$1.png"
}

# Labels this test must never tap. Sending a question fans it out to every
# online teacher covering its topic, so a stray tap is somebody's phone ringing
# for a lesson that nobody meant to book.
FORBIDDEN_LABELS=("Find me a Teacher" "מצא לי מורה" "Send" "שלח")

# The accessibility tree of whatever is on screen, written where the query
# helper can read it.
#
# The device refuses to dump while the UI is animating, and on failure it leaves
# the PREVIOUS dump on disk — read that and the script believes it is looking at
# the last screen while acting on this one. This function fails loudly instead,
# because a stale tree once had the test tapping coordinates from the home
# screen onto the question sheet, which submitted a question.
dump_ui() {
  local output
  "${ADB[@]}" shell rm -f /sdcard/ui.xml >/dev/null 2>&1 || true
  output="$("${ADB[@]}" shell uiautomator dump /sdcard/ui.xml 2>&1 || true)"
  if [[ "$output" != *"dumped to"* ]]; then
    sleep 2
    "${ADB[@]}" shell rm -f /sdcard/ui.xml >/dev/null 2>&1 || true
    output="$("${ADB[@]}" shell uiautomator dump /sdcard/ui.xml 2>&1 || true)"
  fi
  if [[ "$output" != *"dumped to"* ]]; then
    return 1
  fi
  "${ADB[@]}" shell cat /sdcard/ui.xml > "$DUMP" 2>/dev/null || return 1
  [[ -s "$DUMP" ]] || return 1
}

# Centre of the first node whose text or content-desc contains any argument.
# Prints "x y", or nothing when no node matches.
find_center() {
  dump_ui || return 1
  python3 "$HELPER" center "$DUMP" "$@" 2>/dev/null
}

ui_contains() {
  dump_ui || return 1
  python3 "$HELPER" contains "$DUMP" "$@" 2>/dev/null
}

# Waits for any of the given labels to appear. Timeout in seconds.
wait_for() {
  local timeout="$1"; shift
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    ui_contains "$@" && return 0
    sleep 2
  done
  return 1
}

assert_visible() {
  local label="$1"; shift
  if ui_contains "$@"; then pass "$label"; else fail "$label (not found on screen)"; fi
}

tap_text() {
  local needle forbidden
  for needle in "$@"; do
    for forbidden in "${FORBIDDEN_LABELS[@]}"; do
      if [[ "$needle" == *"$forbidden"* ]]; then
        fail "refusing to tap \"$needle\": that sends the question"
        return 1
      fi
    done
  done
  if ! dump_ui; then
    fail "could not read the screen, so not tapping blind (target: $*)"
    return 1
  fi
  local coords; coords="$(python3 "$HELPER" center "$DUMP" "$@" 2>/dev/null)"
  [[ -n "$coords" ]] || { fail "could not find a tap target for: $*"; return 1; }
  # shellcheck disable=SC2086
  "${ADB[@]}" shell input tap $coords
  sleep 2
}

# For labels that appear more than once. The ask-a-teacher sheet carries
# "Algebra" twice: once as a topic chip and once as the keyboard switch below
# it, and the switch is the later of the two.
tap_last() {
  if ! dump_ui; then
    fail "could not read the screen, so not tapping blind (target: $*)"
    return 1
  fi
  local coords; coords="$(python3 "$HELPER" center_last "$DUMP" "$@" 2>/dev/null)"
  [[ -n "$coords" ]] || { fail "could not find a tap target for: $*"; return 1; }
  # shellcheck disable=SC2086
  "${ADB[@]}" shell input tap $coords
  sleep 2
}

type_into() {
  local coords; coords="$(find_center "$1")"
  [[ -n "$coords" ]] || { fail "could not find field: $1"; return 1; }
  # shellcheck disable=SC2086
  "${ADB[@]}" shell input tap $coords
  sleep 1
  "${ADB[@]}" shell input text "$(sed 's/ /%s/g' <<<"$2")"
  sleep 1
}

restore_animations() {
  (( ANIMATIONS_OFF == 1 )) || return 0
  for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
    "${ADB[@]}" shell settings put global "$scale" 1 >/dev/null 2>&1 || true
  done
}
trap restore_animations EXIT

if (( ANIMATIONS_OFF == 1 )); then
  for scale in window_animation_scale transition_animation_scale animator_duration_scale; do
    "${ADB[@]}" shell settings put global "$scale" 0 >/dev/null 2>&1 || true
  done
fi

log "Device $DEVICE"

# ---------------------------------------------------------------- launch
if (( KEEP_DATA == 0 && SKIP_LOGIN == 0 )); then
  log "Clearing app data (signs the device out)"
  "${ADB[@]}" shell pm clear "$PACKAGE" >/dev/null
fi

log "Launching the app"
"${ADB[@]}" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
"${ADB[@]}" shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null
# The debug build loads a large JNI bundle, so first paint is slow.
wait_for 180 "Welcome" "ברוך" "Log In" "התחבר" "Ask a question" "שאל שאלה" || true
shot launch

# ---------------------------------------------------------------- sign in
if (( SKIP_LOGIN == 0 )); then
  log "Signing in as $EMAIL"
  if ui_contains "Log In" "התחבר" "Sign In"; then
    tap_text "Log In" "התחבר" "Sign In" || true
    sleep 2
  fi
  wait_for 30 "Email" "אימייל" "Password" "סיסמה" \
    || fail "the sign-in form never appeared"
  type_into "Email" "$EMAIL" || type_into "אימייל" "$EMAIL" || true
  "${ADB[@]}" shell input keyevent KEYCODE_ESCAPE >/dev/null 2>&1 || true
  type_into "Password" "$PASSWORD" || type_into "סיסמה" "$PASSWORD" || true
  "${ADB[@]}" shell input keyevent KEYCODE_ESCAPE >/dev/null 2>&1 || true
  shot credentials-entered
  tap_text "Log In" "התחבר" || true

  if wait_for 90 "Ask a question" "שאל שאלה"; then
    pass "signed in and reached the home screen"
  else
    fail "did not reach the home screen after signing in"
  fi
  shot after-login
fi

# ------------------------------------------------------------ home screen
log "Checking the home screen"
assert_visible "the ask-a-question button is on screen" "Ask a question" "שאל שאלה"
assert_visible "the minutes balance is shown" "Total minutes" "סך כל הדקות"
assert_visible "the subjects section is shown" "Available Subjects" "מקצועות זמינים"
# Below the fold on a phone, so scroll to it rather than calling it missing.
"${ADB[@]}" shell input swipe 540 1500 540 700 400 >/dev/null 2>&1 || true
sleep 2
assert_visible "the how-it-works panel is shown" "How it works" "איך זה עובד"
"${ADB[@]}" shell input swipe 540 700 540 1500 400 >/dev/null 2>&1 || true
sleep 2

log "Checking the tab bar"
assert_visible "Home tab" "Home" "בית"
assert_visible "Lessons tab" "Lessons" "שיעורים"
assert_visible "Profile tab" "Profile" "פרופיל"
assert_visible "Settings tab" "Settings" "הגדרות"
# Icons are text glyphs on Android, and the ones that stand on their own reach
# the accessibility tree. The tab bar's do not: Compose merges each tab's icon
# into the tab's own node, which carries the label alone — so the screenshots
# below are what covers those, and a tab icon that vanishes is caught by eye.
assert_visible "the header logo icon" "📚"
assert_visible "the ask-a-question button icon" "✋"
# "●" is the icon table's fallback for a name it does not know, so finding one
# anywhere means an icon lost its glyph.
if ui_contains "●"; then
  fail "an icon fell back to the missing-icon dot"
else
  pass "no icon fell back to the missing-icon dot"
fi
shot home

# --------------------------------------------------------- ask a question
log "Opening the ask-a-teacher sheet"
tap_text "Ask a question" "שאל שאלה" || true
if wait_for 30 "Your question" "השאלה שלך"; then
  pass "the ask-a-teacher sheet opened"
else
  # Fatal on purpose. Everything below types and taps, and doing that against a
  # screen the test cannot identify is how a question got submitted once.
  fail "the ask-a-teacher sheet did not open, or could not be read"
  echo "The sheet focuses its question field on open, and uiautomator will not"
  echo "dump a screen whose caret is blinking — 'could not get idle state'."
  echo "Re-run with --animations-off, which is the usual remedy."
  echo "FAILED: stopping rather than typing into an unidentified screen"
  exit 1
fi
assert_visible "the session type section" "Session type" "סוג שיעור"
assert_visible "the topic section" "Topic" "נושא"
assert_visible "the photo section" "Attach a photo" "צירוף תמונה"
shot sheet-open

log "Writing the question"
QUESTION="How do I solve this equation"
"${ADB[@]}" shell input text "$(sed 's/ /%s/g' <<<"$QUESTION")"
sleep 2
if ui_contains "$QUESTION"; then
  pass "the question text was typed into the field"
else
  fail "the question text did not reach the field"
fi
shot question-typed

# ------------------------------------------------------ algebra keyboard
log "Switching to the algebra keyboard"
tap_last "Algebra" "אלגברה" || true
sleep 2
if wait_for 20 "Clear" "π"; then
  pass "the algebra pad is on screen"
else
  fail "the algebra pad did not appear"
  echo "FAILED: stopping rather than tapping keys that are not there"
  exit 1
fi
for key in "x²" "√" "π"; do
  assert_visible "the $key key is on the pad" "$key"
done
shot algebra-pad

log "Typing a formula"
tap_text "7" || true
tap_text "+" || true
tap_text "3" || true
shot formula-entered

log "Switching back to the regular keyboard"
tap_last "Regular" "רגיל" || true
sleep 2
if ui_contains "Clear"; then
  fail "the algebra pad is still on screen after switching back"
else
  pass "the algebra pad stepped aside for the regular keyboard"
fi
shot back-to-regular

# The question is deliberately left unsent.
log "Done. Screenshots: $ARTIFACTS"
if (( FAILURES > 0 )); then
  echo "FAILED: $FAILURES check(s)"
  exit 1
fi
echo "PASSED"
