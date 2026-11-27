#!/usr/bin/env bash
#
# Builds the Staging apps (staging Firebase project) and uploads them for
# testing: Android to Google Play's internal track, iOS to TestFlight.
#
#   scripts/release-staging.sh [both|student|teacher]     (default: both)
#
# The same as scripts/release-all.sh, with TIM_BUILD=staging: the Android
# "staging" build type and the Xcode "Staging" configuration, which keep the
# apps' real ids (com.yaronj.student, com.yaronj.tim). The same environment
# variables apply: PLAY_JSON_KEY (required), PLAY_TRACK, ASC_KEY_*.
#
# Either half alone:
#   TIM_BUILD=staging scripts/bundle-android.sh [both|student|teacher]
#   TIM_BUILD=staging scripts/archive-ios.sh [both|student|teacher]
set -euo pipefail
export TIM_BUILD=staging
exec "$(cd "$(dirname "$0")" && pwd)/release-all.sh" "$@"
