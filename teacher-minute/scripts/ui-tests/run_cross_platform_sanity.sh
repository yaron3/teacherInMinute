#!/usr/bin/env bash
#
# Cross-platform sanity: a live text lesson between an iPhone simulator and an
# Android emulator, against the local Firebase emulators, in both directions:
#
#   ios-student      Instant Teacher on the iPhone asks; Pro Teacher on Android
#                    takes it, and ends it after 35 seconds; the student closes
#                    the rating and finds the lesson in its history
#   android-student  Instant Teacher on Android asks; Pro Teacher on the iPhone
#                    takes it and ends it; the student closes the rating
#   ios-student-block  (only when named) Instant Teacher on the iPhone takes a
#                    lesson from Pro Teacher on Android, then reports and
#                    blocks them; a question asked then never shows on the
#                    teacher's screen; after unblocking in Privacy Controls the
#                    next one does (IT-42)
#
# Each direction runs its two halves at the same time; they meet only through
# the emulators (see CrossPlatformLessonTest.kt for the protocol). The iOS
# halves are the lesson tests' own (StudentAskUITests, ProTeacherLessonUITests).
#
# Nothing here leaves the machine. Start the emulators first:
#
#     npm --prefix backend/Firebase/functions run emulators:app
#
# Usage:
#   scripts/ui-tests/run_cross_platform_sanity.sh <ios-simulator-udid> <android-serial> [direction]
#
# The Android app and test APKs are built and installed first; set
# SKIP_ANDROID_BUILD=1 to install the ones already built. QUESTION_TEXT words
# the question (default "Sanity test - Dont answer"). Results land in
# $RESULTS_DIR (default: a temporary folder). SKIP_IOS_BUILD=1 reuses the last
# iOS UI-test build.
#
# SESSION_SHOTS=1 also has every half photograph the lesson's stages (invite or
# search, start, middle with a message each way, end, after) into
# $SHOTS_DIR/<direction>/<platform>-<side>/; run_session_screenshots.sh drives
# it across Android screen sizes.

set -euo pipefail

IOS_SIM="${1:?iOS simulator UDID}"
ANDROID="${2:?Android emulator serial, e.g. emulator-5558}"
ONLY="${3:-}"
HOST="${EMULATOR_HOST:-127.0.0.1}"
PROJECT="demo-teacher-in-a-moment"
QUESTION_TEXT="${QUESTION_TEXT:-Sanity test - Dont answer}"
RESULTS_DIR="${RESULTS_DIR:-$(mktemp -d -t cross-sanity)}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$RESULTS_DIR"
APK="$ROOT/.build/Android/app/outputs/apk"

curl -sf "http://$HOST:9099/" > /dev/null || { echo "Firebase emulators not running on $HOST" >&2; exit 1; }
adb -s "$ANDROID" get-state > /dev/null || { echo "no Android device $ANDROID" >&2; exit 1; }

# 1. The teacher, on the emulators only. "Lesson Teacher" is the name the iOS
#    student's half looks for in its history.
new_teacher() {
  local stamp email password signup uid
  stamp="$(date +%s)$RANDOM"
  email="sanity.teacher.$stamp@example.com"
  password="Emulator-$RANDOM$RANDOM"
  signup=$(curl -sf -X POST "http://$HOST:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$password\",\"returnSecureToken\":true}")
  uid=$(printf '%s' "$signup" | python3 -c 'import json,sys; print(json.load(sys.stdin)["localId"])')
  curl -sf -X PATCH \
    "http://$HOST:8085/v1/projects/$PROJECT/databases/(default)/documents/users/$uid?updateMask.fieldPaths=role&updateMask.fieldPaths=fullName&updateMask.fieldPaths=phoneNumber&updateMask.fieldPaths=subjectSelections" \
    -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
    -d '{"fields":{
          "role":{"stringValue":"teacher"},
          "fullName":{"stringValue":"Lesson Teacher"},
          "phoneNumber":{"stringValue":"+972500000000"},
          "subjectSelections":{"mapValue":{"fields":{"math":{"arrayValue":{"values":[{"stringValue":"algebra"}]}}}}}
        }}' > /dev/null
  echo "$email $password $uid"
}

# 2. Build: the iOS UI tests once; the Android apps and their tests.
cd "$ROOT"
if [[ -z "${SKIP_IOS_BUILD:-}" ]]; then
echo "building the iOS UI tests…"
xcodebuild build-for-testing -workspace Project.xcworkspace -scheme "Instant Teacher" \
  -destination "platform=iOS Simulator,id=$IOS_SIM" -skipMacroValidation SKIP_ACTION=none \
  > "$RESULTS_DIR/ios-build.log" 2>&1 || { echo "iOS build failed; see $RESULTS_DIR/ios-build.log" >&2; exit 1; }
fi
if [[ -z "${SKIP_ANDROID_BUILD:-}" ]]; then
  echo "building the Android apps…"
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  export SWIFT_TOOLCHAIN_DIR="${SWIFT_TOOLCHAIN_DIR:-$HOME/Library/Developer/Toolchains-SkipShim}"
  scripts/android-toolchain-shim.sh --quiet
  (cd Android && ./gradlew -q :app:assembleTeacherDebug :app:assembleStudentDebug \
      :app:assembleTeacherDebugAndroidTest :app:assembleStudentDebugAndroidTest) \
    > "$RESULTS_DIR/android-build.log" 2>&1 || { echo "Android build failed; see $RESULTS_DIR/android-build.log" >&2; exit 1; }
fi
for apk in teacher/debug/app-teacher-debug.apk student/debug/app-student-debug.apk \
           androidTest/teacher/debug/app-teacher-debug-androidTest.apk \
           androidTest/student/debug/app-student-debug-androidTest.apk; do
  adb -s "$ANDROID" install -r -t "$APK/$apk" > /dev/null
done

# 3. Each direction's halves at once.
run_ios() {
  local test="$1" name="$2"
  xcodebuild test-without-building -workspace Project.xcworkspace -scheme "Instant Teacher" \
    -destination "platform=iOS Simulator,id=$IOS_SIM" -parallel-testing-enabled NO \
    -only-testing:"TeacherMinuteUITests/$test" -resultBundlePath "$RESULTS_DIR/$name.xcresult" \
    > "$RESULTS_DIR/$name.log" 2>&1
}
run_android() {
  local runner="$1" test="$2" name="$3"
  adb -s "$ANDROID" shell am instrument -w -r \
    -e class "teacher.minute.CrossPlatformLessonTest#$test" \
    -e lessonTeacherEmail "$TEACHER_EMAIL" -e lessonTeacherPassword "$TEACHER_PASSWORD" \
    -e lessonTeacherUid "$TEACHER_UID" -e questionText "'$QUESTION_TEXT'" \
    -e sessionShots "${SESSION_SHOTS:-0}" \
    "$runner/teacher.minute.EmulatorTestRunner" > "$RESULTS_DIR/$name.log" 2>&1
  # am instrument exits 0 whatever the tests did.
  grep -q "^OK (1 test)" "$RESULTS_DIR/$name.log"
}
report() {
  local name="$1"
  echo "== $name"
  grep -E "error: |Test Case .*(passed|failed|skipped)|^OK \(|^FAILURES|Tests run|AssertionError|AssumptionViolated" \
    "$RESULTS_DIR/$name.log" | grep -v "^ *[0-9]* |" | sed 's/.*Tests //' | head -10 || true
}

# Session screenshots: the Android half's from the app's files, the iOS half's
# from its result bundle's attachments.
SHOTS_DIR="${SHOTS_DIR:-$RESULTS_DIR/shots}"
export TEST_RUNNER_SESSION_SHOTS="${SESSION_SHOTS:-0}"
clear_android_shots() {
  for pkg in com.yaronj.tim com.yaronj.student; do
    adb -s "$ANDROID" shell run-as "$pkg" rm -rf files/ui-test/shots > /dev/null 2>&1 || true
  done
}
collect_shots() {
  local direction="$1" android_pkg="$2" android_side="$3" ios_half="$4" ios_side="$5"
  local adir="$SHOTS_DIR/$direction/android-$android_side" idir="$SHOTS_DIR/$direction/ios-$ios_side"
  mkdir -p "$adir" "$idir"
  for f in $(adb -s "$ANDROID" shell run-as "$android_pkg" ls files/ui-test/shots 2>/dev/null | tr -d '\r'); do
    adb -s "$ANDROID" exec-out run-as "$android_pkg" cat "files/ui-test/shots/$f" > "$adir/$f"
  done
  local raw="$RESULTS_DIR/$ios_half-attachments"
  rm -rf "$raw"
  xcrun xcresulttool export attachments --path "$RESULTS_DIR/$ios_half.xcresult" --output-path "$raw" > /dev/null 2>&1 || true
  [[ -f "$raw/manifest.json" ]] && python3 - "$raw" "$idir" <<'PY'
import json, shutil, sys, os
raw, out = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "")
        if name.startswith("shot-"):
            # "shot-02-teacher-lesson-start_0_<uuid>.png" -> "02-teacher-lesson-start.png"
            clean = name[len("shot-"):].split("_")[0]
            shutil.copy(os.path.join(raw, a["exportedFileName"]), os.path.join(out, clean + ".png"))
PY
}

status=0
for direction in ios-student android-student ios-student-block; do
  [[ -n "$ONLY" && "$ONLY" != "$direction" ]] && continue
  [[ -z "$ONLY" && "$direction" == ios-student-block ]] && continue
  [[ "${SESSION_SHOTS:-0}" == 1 ]] && clear_android_shots
  read -r TEACHER_EMAIL TEACHER_PASSWORD TEACHER_UID <<< "$(new_teacher)"
  echo "$direction: teacher $TEACHER_EMAIL uid=$TEACHER_UID"
  export TEST_RUNNER_LESSON_TEACHER_EMAIL="$TEACHER_EMAIL"
  export TEST_RUNNER_LESSON_TEACHER_PASSWORD="$TEACHER_PASSWORD"
  export TEST_RUNNER_LESSON_TEACHER_UID="$TEACHER_UID"
  export TEST_RUNNER_QUESTION_TEXT="$QUESTION_TEXT"
  if [[ "$direction" == "ios-student-block" ]]; then
    run_android com.yaronj.tim.test teachesThenIsBlockedThenUnblocked "$direction-android-teacher" &
    teacher_pid=$!
    run_ios StudentAskUITests/testABlockedTeacherGetsNoQuestionsUntilUnblocked "$direction-ios-student" &
    student_pid=$!
    halves=("$direction-android-teacher" "$direction-ios-student")
  elif [[ "$direction" == "ios-student" ]]; then
    run_android com.yaronj.tim.test teachesALessonAndEndsIt "$direction-android-teacher" &
    teacher_pid=$!
    run_ios StudentAskUITests/testTakingALessonTheTeacherEndsThenSkippingTheRating "$direction-ios-student" &
    student_pid=$!
    halves=("$direction-android-teacher" "$direction-ios-student")
  else
    run_ios ProTeacherLessonUITests/testTeachingALessonAndEndingIt "$direction-ios-teacher" &
    teacher_pid=$!
    run_android com.yaronj.student.test asksAndTakesALesson "$direction-android-student" &
    student_pid=$!
    halves=("$direction-ios-teacher" "$direction-android-student")
  fi
  wait "$teacher_pid" || status=1
  wait "$student_pid" || status=1
  for half in "${halves[@]}"; do report "$half"; done
  if [[ "${SESSION_SHOTS:-0}" == 1 ]]; then
    if [[ "$direction" == "ios-student" ]]; then
      collect_shots "$direction" com.yaronj.tim teacher "$direction-ios-student" student
    else
      collect_shots "$direction" com.yaronj.student student "$direction-ios-teacher" teacher
    fi
  fi
done
echo "results in $RESULTS_DIR"
[[ "$status" == 0 ]] && echo "SANITY PASSED" || echo "SANITY FAILED"
exit "$status"
