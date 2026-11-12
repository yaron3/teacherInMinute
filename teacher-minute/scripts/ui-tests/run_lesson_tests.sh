#!/usr/bin/env bash
#
# Live lessons between two simulators, against the local Firebase emulators:
# Instant Teacher as the student on one (StudentAskUITests), Pro Teacher as
# the teacher on the other (ProTeacherLessonUITests). Each pair of halves runs
# at the same time and meets only through the emulators; the pairs run one
# after another, all with the same teacher:
#
#   student-ends  a message each way and a stroke on the board, then the
#                 student ends, rates, finds it in history; the teacher finds
#                 it in Lessons and Earnings (IOS-D-12, L-02, L-03, R-01, R-05,
#                 M-07)
#   teacher-ends  the teacher ends; the student closes the rating (L-04, R-02)
#   report        the student ends, then reports and blocks the teacher
#                 (R-03, R-04)
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
#   scripts/ui-tests/run_lesson_tests.sh <student-simulator-udid> <teacher-simulator-udid> [pair]
#
# With a pair's name, only that pair runs.
#
# Both simulators must be booted and of the same device type. Results land in
# $RESULTS_DIR (default: a temporary folder), one .xcresult per half.

set -euo pipefail

STUDENT_SIM="${1:?student simulator UDID}"
TEACHER_SIM="${2:?teacher simulator UDID}"
ONLY="${3:-}"
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

# 3. Each pair's halves at once, the pairs one after another.
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
PAIRS=(
  "student-ends|ProTeacherLessonUITests/testTeachingALessonTheStudentEnds|StudentAskUITests/testTakingALessonThenEndingAndRatingIt"
  "teacher-ends|ProTeacherLessonUITests/testTeachingALessonAndEndingIt|StudentAskUITests/testTakingALessonTheTeacherEndsThenSkippingTheRating"
  "report|ProTeacherLessonUITests/testTeachingALessonTheStudentEndsAndReports|StudentAskUITests/testEndingALessonThenReportingAndBlockingTheTeacher"
)
status=0
for pair in "${PAIRS[@]}"; do
  IFS='|' read -r name teacher_test student_test <<< "$pair"
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue
  run_half "$TEACHER_SIM" "$teacher_test" "$name-teacher" &
  teacher_pid=$!
  run_half "$STUDENT_SIM" "$student_test" "$name-student" &
  student_pid=$!
  wait "$teacher_pid" || status=1
  wait "$student_pid" || status=1
  for half in teacher student; do
    echo "== $name, $half"
    grep -E "error: |Test Case .*(passed|failed|skipped)" "$RESULTS_DIR/$name-$half.log" | grep -v "^ *[0-9]* |" | sed 's/.*Tests //' || true
  done
done
echo "results in $RESULTS_DIR"
exit "$status"
