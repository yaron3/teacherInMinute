#!/usr/bin/env bash
#
# A live lesson between two simulators, against the local Firebase emulators:
# Instant Teacher as the student on one (StudentAskUITests
# .testTakingALessonThenEndingAndRatingIt), Pro Teacher as the teacher on the
# other (ProTeacherLessonUITests.testTeachingALessonTheStudentEnds). The two
# halves meet only through the emulators. QA test plan IOS-L-03 and IOS-R-01.
#
# What it does:
#   1. creates a teacher account on the emulators (Auth + its users/{uid});
#   2. builds the UI tests once;
#   3. runs both halves at the same time, each on its own simulator, with the
#      teacher's account handed in through TEST_RUNNER_* variables.
#
# Nothing here leaves the machine: the account and the lesson live only on the
# emulators. Start them first:
#
#     npm --prefix backend/Firebase/functions run emulators:app
#
# Usage:
#   scripts/ui-tests/run_lesson_tests.sh <student-simulator-udid> <teacher-simulator-udid>
#
# Both simulators must be booted and of the same device type. Results land in
# $RESULTS_DIR (default: a temporary folder), one .xcresult per half.

set -euo pipefail

STUDENT_SIM="${1:?student simulator UDID}"
TEACHER_SIM="${2:?teacher simulator UDID}"
HOST="${EMULATOR_HOST:-127.0.0.1}"
PROJECT="demo-teacher-in-a-moment"
RESULTS_DIR="${RESULTS_DIR:-$(mktemp -d -t lesson-tests)}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

curl -sf "http://$HOST:9099/" > /dev/null || { echo "Firebase emulators not running on $HOST" >&2; exit 1; }

# 1. The teacher, on the emulators only.
STAMP="$(date +%s)"
TEACHER_EMAIL="lesson.teacher.$STAMP@example.com"
TEACHER_PASSWORD="Emulator-$RANDOM$RANDOM"
SIGNUP=$(curl -sf -X POST "http://$HOST:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$TEACHER_EMAIL\",\"password\":\"$TEACHER_PASSWORD\",\"returnSecureToken\":true}")
TEACHER_UID=$(printf '%s' "$SIGNUP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["localId"])')
curl -sf -X PATCH \
  "http://$HOST:8085/v1/projects/$PROJECT/databases/(default)/documents/users/$TEACHER_UID?updateMask.fieldPaths=role&updateMask.fieldPaths=fullName&updateMask.fieldPaths=phoneNumber&updateMask.fieldPaths=subjectSelections" \
  -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
  -d '{"fields":{
        "role":{"stringValue":"teacher"},
        "fullName":{"stringValue":"Lesson Teacher"},
        "phoneNumber":{"stringValue":"+972500000000"},
        "subjectSelections":{"mapValue":{"fields":{"math":{"arrayValue":{"values":[{"stringValue":"algebra"}]}}}}}
      }}' > /dev/null
echo "teacher $TEACHER_EMAIL uid=$TEACHER_UID"

# 2. Build once.
cd "$ROOT"
xcodebuild build-for-testing -workspace Project.xcworkspace -scheme "Instant Teacher" \
  -destination "platform=iOS Simulator,id=$STUDENT_SIM" -skipMacroValidation SKIP_ACTION=none \
  > "$RESULTS_DIR/build.log" 2>&1 || { echo "build failed; see $RESULTS_DIR/build.log" >&2; exit 1; }

# 3. Both halves at once.
export TEST_RUNNER_LESSON_TEACHER_EMAIL="$TEACHER_EMAIL"
export TEST_RUNNER_LESSON_TEACHER_PASSWORD="$TEACHER_PASSWORD"
export TEST_RUNNER_LESSON_TEACHER_UID="$TEACHER_UID"
run_half() {
  local sim="$1" test="$2" name="$3"
  xcodebuild test-without-building -workspace Project.xcworkspace -scheme "Instant Teacher" \
    -destination "platform=iOS Simulator,id=$sim" -parallel-testing-enabled NO \
    -only-testing:"TeacherMinuteUITests/$test" -resultBundlePath "$RESULTS_DIR/$name.xcresult" \
    > "$RESULTS_DIR/$name.log" 2>&1
}
run_half "$TEACHER_SIM" "ProTeacherLessonUITests/testTeachingALessonTheStudentEnds" teacher &
TEACHER_PID=$!
run_half "$STUDENT_SIM" "StudentAskUITests/testTakingALessonThenEndingAndRatingIt" student &
STUDENT_PID=$!
status=0
wait "$TEACHER_PID" || status=1
wait "$STUDENT_PID" || status=1

for name in teacher student; do
  echo "== $name"
  grep -E "error: |Test Case .*(passed|failed|skipped)" "$RESULTS_DIR/$name.log" | grep -v "^ *[0-9]* |" | sed 's/.*Tests //' || true
done
echo "results in $RESULTS_DIR"
exit "$status"
