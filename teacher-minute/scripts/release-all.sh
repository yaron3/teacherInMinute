#!/usr/bin/env bash
#
# Builds and uploads all four apps in one go: Android first, then iOS.
#
#   scripts/release-all.sh [both|student|teacher]     (default: both)
#
#   1. scripts/bundle-android.sh  → Google Play, internal track, draft
#      (Instant Teacher com.yaronj.student, Pro Teacher com.yaronj.tim)
#   2. scripts/archive-ios.sh     → App Store Connect / TestFlight
#      (the same two apps)
#
# Each step raises its own build number first: the Android version code in
# Skip.env, the iOS build number in the Xcode project. If Android fails, iOS
# does not start. Commit both bumps afterwards.
#
# Needs PLAY_JSON_KEY (see bundle-android.sh), so a run never builds the
# Android bundles without uploading them.

set -euo pipefail

WHICH="${1:-both}"
HERE="$(cd "$(dirname "$0")" && pwd)"

case "$WHICH" in
  both|student|teacher) ;;
  *) echo "usage: $0 [both|student|teacher]" >&2; exit 2 ;;
esac

if [[ -z "${PLAY_JSON_KEY:-}" || ! -f "$PLAY_JSON_KEY" ]]; then
  echo "PLAY_JSON_KEY is not set to a Google Play service account key; the Android bundles would not be uploaded." >&2
  exit 1
fi

start=$(date +%s)
echo "######## Android ########"
"$HERE/bundle-android.sh" "$WHICH"
echo
echo "######## iOS ########"
"$HERE/archive-ios.sh" "$WHICH"
echo
echo "All done in $(( ($(date +%s) - start) / 60 )) min: Android on Play's ${PLAY_TRACK:-internal} track, iOS on App Store Connect."
