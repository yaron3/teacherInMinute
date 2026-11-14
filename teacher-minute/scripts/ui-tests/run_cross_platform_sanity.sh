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
# $RESULTS_DIR (default: a temporary folder).

set -euo pipefail

IOS_SIM="${1:?iOS simulator UDID}"
ANDROID="${2:?Android emulator serial, e.g. emulator-5558}"
ONLY="${3:-}"
HOST="${EMULATOR_HOST:-127.0.0.1}"
PROJECT="demo-teacher-in-a-moment"
QUESTION_TEXT="${QUESTION_TEXT:-Sanity test - Dont answer}"
RESULTS_DIR="${RESULTS_DIR:-$(mktemp -d -t cross-sanity)}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
echo "building the iOS UI tests…"
xcodebuild build-for-testing -workspace Project.xcworkspace -scheme "Instant Teacher" \
  -destination "platform=iOS Simulator,id=$IOS_SIM" -skipMacroValidation SKIP_ACTION=none \
  > "$RESULTS_DIR/ios-build.log" 2>&1 || { echo "iOS build failed; see $RESULTS_DIR/ios-build.log" >&2; exit 1; }
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

status=0
for direction in ios-student android-student; do
  [[ -n "$ONLY" && "$ONLY" != "$direction" ]] && continue
  read -r TEACHER_EMAIL TEACHER_PASSWORD TEACHER_UID <<< "$(new_teacher)"
  echo "$direction: teacher $TEACHER_EMAIL uid=$TEACHER_UID"
  export TEST_RUNNER_LESSON_TEACHER_EMAIL="$TEACHER_EMAIL"
  export TEST_RUNNER_LESSON_TEACHER_PASSWORD="$TEACHER_PASSWORD"
  export TEST_RUNNER_LESSON_TEACHER_UID="$TEACHER_UID"
  export TEST_RUNNER_QUESTION_TEXT="$QUESTION_TEXT"
  if [[ "$direction" == "ios-student" ]]; then
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
done
echo "results in $RESULTS_DIR"
[[ "$status" == 0 ]] && echo "SANITY PASSED" || echo "SANITY FAILED"
exit "$status"
