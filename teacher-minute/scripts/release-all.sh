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

# The body sits in one { } block, so bash reads the whole file before it
# runs any of it: editing the script during a run cannot break that run.
{
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

# Check the App Store Connect key now, not after the Android half has run.
if [[ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]]; then
  if [[ -z "${ASC_KEY_PATH:-}" || -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || ! -f "${ASC_KEY_PATH:-}" ]]; then
    echo "ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID must all be set, and ASC_KEY_PATH must exist (see archive-ios.sh)." >&2
    exit 1
  fi
else
  echo "Note: no ASC_KEY_* set; the iOS upload will use the Apple account signed in to Xcode." >&2
fi

start=$(date +%s)
stamp() { echo "[$(date +%H:%M:%S) +$(( ($(date +%s) - start) / 60 ))m] $*"; }
stamp "Release of $WHICH started $(date '+%Y-%m-%d %H:%M')"

echo
echo "######## 1/2 Android ########"
stamp "Starting Android…"
"$HERE/bundle-android.sh" "$WHICH" || { stamp "Android FAILED; iOS was not started."; exit 1; }
stamp "Android complete."

echo
echo "######## 2/2 iOS ########"
stamp "Starting iOS…"
"$HERE/archive-ios.sh" "$WHICH" || { stamp "iOS FAILED (Android was already uploaded)."; exit 1; }
stamp "iOS complete."

echo
stamp "All done in $(( ($(date +%s) - start) / 60 )) min: Android on Play's ${PLAY_TRACK:-internal} track, iOS on App Store Connect."
exit
}
