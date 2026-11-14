#!/usr/bin/env bash
#
# Builds the signed Android App Bundles (.aab) for Google Play, and uploads
# them when a Play service account key is given.
#
#   scripts/bundle-android.sh [both|student|teacher]     (default: both)
#
#   student  Instant Teacher  com.yaronj.student
#   teacher  Pro Teacher      com.yaronj.tim
#
# Before building, the version code goes up by one. Play refuses a version code
# it has already seen, so every run gets a new one. Android takes it from
# CURRENT_PROJECT_VERSION in Skip.env (the iOS build number lives in the Xcode
# project instead; scripts/archive-ios.sh bumps that one). Both apps get the
# same code, and each bundle is checked to carry it. The bump stays in the
# working tree for you to commit.
#
# Signing uses Android/app/keystore.properties (or the TEACHER_MINUTE_UPLOAD_*
# environment variables; see keystore.properties.example).
#
# After the build:
#   - The native debug symbols go to Crashlytics, so Swift crashes on Android
#     come back symbolicated. CRASHLYTICS=0 skips it.
#   - With PLAY_JSON_KEY set to a Google Play service account key, fastlane
#     uploads each bundle to Play: track PLAY_TRACK (default internal), as a
#     draft release (PLAY_RELEASE_STATUS, default draft) that you roll out in
#     Play Console. Without it, the bundles wait in build/android-bundles for
#     you to upload in Play Console.

# The body sits in one { } block, so bash reads the whole file before it
# runs any of it: editing the script during a run cannot break that run.
{
set -euo pipefail

START=$(date +%s)
# Progress line with the clock time and the minutes since this script started.
say() { echo "[$(date +%H:%M:%S) +$(( ($(date +%s) - START) / 60 ))m] $*"; }

WHICH="${1:-both}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKIP_ENV="$ROOT/Skip.env"
OUT="$ROOT/build/android-bundles"
BUNDLES="$ROOT/.build/Android/app/outputs/bundle"

case "$WHICH" in
  both)    FLAVORS=(student teacher) ;;
  student) FLAVORS=(student) ;;
  teacher) FLAVORS=(teacher) ;;
  *) echo "usage: $0 [both|student|teacher]" >&2; exit 2 ;;
esac

package_of() { [[ "$1" == student ]] && echo com.yaronj.student || echo com.yaronj.tim; }
name_of()    { [[ "$1" == student ]] && echo InstantTeacher || echo ProTeacher; }
capital()    { echo "$(tr '[:lower:]' '[:upper:]' <<< "${1:0:1}")${1:1}"; }

if [[ -n "${PLAY_JSON_KEY:-}" && ! -f "$PLAY_JSON_KEY" ]]; then
  echo "PLAY_JSON_KEY points to $PLAY_JSON_KEY, which does not exist" >&2; exit 1
fi

# 1. Bump the version code.
OLD=$(sed -n 's/^CURRENT_PROJECT_VERSION *= *\([0-9][0-9]*\).*/\1/p' "$SKIP_ENV")
VERSION=$(sed -n 's/^MARKETING_VERSION *= *\([^ ]*\).*/\1/p' "$SKIP_ENV")
[[ -n "$OLD" && -n "$VERSION" ]] || { echo "no CURRENT_PROJECT_VERSION or MARKETING_VERSION in $SKIP_ENV" >&2; exit 1; }
NEW=$((OLD + 1))
sed -i '' "s/^CURRENT_PROJECT_VERSION *= *$OLD\$/CURRENT_PROJECT_VERSION = $NEW/" "$SKIP_ENV"
grep -q "^CURRENT_PROJECT_VERSION = $NEW\$" "$SKIP_ENV" || { echo "could not update $SKIP_ENV" >&2; exit 1; }
say "Android: started $(date '+%Y-%m-%d %H:%M')"
say "Android: version code $OLD → $NEW (version $VERSION)"

# 2. Build the bundles (and upload their symbols).
mkdir -p "$OUT"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export SWIFT_TOOLCHAIN_DIR="${SWIFT_TOOLCHAIN_DIR:-$HOME/Library/Developer/Toolchains-SkipShim}"
"$ROOT/scripts/android-toolchain-shim.sh" --quiet

TASKS=()
for flavor in "${FLAVORS[@]}"; do
  variant="$(capital "$flavor")Release"
  TASKS+=(":app:bundle$variant")
  [[ "${CRASHLYTICS:-1}" == "0" ]] || TASKS+=(":app:uploadCrashlyticsSymbolFile$variant")
done
say "Android: building ${FLAVORS[*]} (about 10 minutes; log: $OUT/gradle.log)…"
(cd "$ROOT/Android" && ./gradlew "${TASKS[@]}") > "$OUT/gradle.log" 2>&1 \
  || { say "Android: build FAILED; see $OUT/gradle.log" >&2; exit 1; }
say "Android: build complete"

# 3. Check, collect and upload each bundle.
for flavor in "${FLAVORS[@]}"; do
  built="$BUNDLES/${flavor}Release/app-$flavor-release.aab"
  aab="$OUT/$(name_of "$flavor")-$VERSION-$NEW.aab"
  code=$(bundletool dump manifest --bundle "$built" --xpath /manifest/@android:versionCode)
  [[ "$code" == "$NEW" ]] || { say "Android: $built has version code $code, not $NEW" >&2; exit 1; }
  cp "$built" "$aab"
  say "Android: $(name_of "$flavor") bundle ready: $aab"

  if [[ -n "${PLAY_JSON_KEY:-}" ]]; then
    say "Android: $(name_of "$flavor") uploading to Play (${PLAY_TRACK:-internal}, ${PLAY_RELEASE_STATUS:-draft})…"
    fastlane run upload_to_play_store \
      package_name:"$(package_of "$flavor")" aab:"$aab" json_key:"$PLAY_JSON_KEY" \
      track:"${PLAY_TRACK:-internal}" release_status:"${PLAY_RELEASE_STATUS:-draft}" \
      skip_upload_apk:true skip_upload_metadata:true skip_upload_changelogs:true \
      skip_upload_images:true skip_upload_screenshots:true \
      > "$OUT/$(name_of "$flavor")-upload.log" 2>&1 \
      || { say "Android: $(name_of "$flavor") upload FAILED; see $OUT/$(name_of "$flavor")-upload.log" >&2; exit 1; }
    say "Android: $(name_of "$flavor") uploaded"
  fi
done

if [[ -n "${PLAY_JSON_KEY:-}" ]]; then
  say "Android: done, uploaded $VERSION ($NEW) to Play's ${PLAY_TRACK:-internal} track."
else
  say "Android: done, built $VERSION ($NEW). Upload the .aab files in $OUT in Play Console, or set PLAY_JSON_KEY to upload them."
fi
echo "Commit the version code bump in $SKIP_ENV."
exit
}
