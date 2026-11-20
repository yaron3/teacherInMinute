#!/usr/bin/env bash
#
# Screenshots of live lessons between an iPhone and an Android phone, at
# several Android screen sizes, against the local Firebase emulators.
#
# For each size, run_cross_platform_sanity.sh runs both directions with
# SESSION_SHOTS=1:
#
#   ios-student      Instant Teacher on the iPhone, Pro Teacher on Android
#   android-student  Instant Teacher on Android, Pro Teacher on the iPhone
#
# and every half photographs: 01 the invite (teacher) or the search (student),
# 02 the lesson's start, 03 its middle after a message each way, 04 the end
# (the teacher's confirmation, the student's rating), 05 the screen after it.
#
# One Android emulator stands in for every size: its screen is resized with
# `wm size` / `wm density` and put back as it was at the end.
#
# Nothing here leaves the machine. Start the emulators first:
#
#     npm --prefix backend/Firebase/functions run emulators:app
#
# Usage:
#   scripts/ui-tests/run_session_screenshots.sh <ios-simulator-udid> <android-serial> [out-dir]
#
# SIZES overrides the sizes, as space-separated name:WxH:dpi, e.g.
#   SIZES="tiny:480x800:240 large:1080x2424:420"
# The default covers a tiny phone (320x533 dp), a small one (360x640 dp) and a
# large one (411x923 dp, a Pixel 10).

set -euo pipefail

IOS_SIM="${1:?iOS simulator UDID}"
ANDROID="${2:?Android emulator serial, e.g. emulator-5554}"
OUT="${3:-$(mktemp -d -t session-shots)}"
SIZES="${SIZES:-tiny:480x800:240 small:720x1280:320 large:1080x2424:420}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT"

# The emulator's screen as found, to put back.
orig_size=$(adb -s "$ANDROID" shell wm size | sed -n 's/^Override size: //p' | tr -d '\r')
orig_density=$(adb -s "$ANDROID" shell wm density | sed -n 's/^Override density: //p' | tr -d '\r')
restore() {
  settle || true
  if [[ -n "$orig_size" ]]; then adb -s "$ANDROID" shell wm size "$orig_size"; else adb -s "$ANDROID" shell wm size reset; fi
  if [[ -n "$orig_density" ]]; then adb -s "$ANDROID" shell wm density "$orig_density"; else adb -s "$ANDROID" shell wm density reset; fi
}
trap restore EXIT

# A resize restarts much of the emulator's UI, and for a while its package
# and window services refuse calls ("Broken pipe"). Wait until both answer.
settle() {
  sleep 5
  for _ in $(seq 1 60); do
    if adb -s "$ANDROID" shell cmd package list packages com.yaronj.tim 2>/dev/null | grep -q com.yaronj.tim &&
       adb -s "$ANDROID" shell wm size > /dev/null 2>&1; then
      sleep 5
      return 0
    fi
    sleep 2
  done
  echo "the emulator did not settle after resizing" >&2
  return 1
}

# Same status bar on every iPhone shot.
xcrun simctl status_bar "$IOS_SIM" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true

status=0
first=1
for spec in $SIZES; do
  IFS=: read -r name size dpi <<< "$spec"
  echo "=== $name: $size @ ${dpi}dpi"
  adb -s "$ANDROID" shell wm size "$size"
  adb -s "$ANDROID" shell wm density "$dpi"
  settle
  # Build once, on the first size; reuse it after.
  if [[ "$first" == 1 ]]; then build_env=(); else build_env=(SKIP_ANDROID_BUILD=1 SKIP_IOS_BUILD=1); fi
  env ${build_env[@]+"${build_env[@]}"} SESSION_SHOTS=1 SHOTS_DIR="$OUT/$name" RESULTS_DIR="$OUT/$name/results" \
    "$HERE/run_cross_platform_sanity.sh" "$IOS_SIM" "$ANDROID" || status=1
  first=0
done

echo "screenshots in $OUT"
find "$OUT" -path "*/results" -prune -o -name "*.png" -print | sort
exit "$status"
