#!/usr/bin/env bash
#
# Archives the iOS apps and uploads them to App Store Connect.
#
#   scripts/archive-ios.sh [both|student|teacher]     (default: both)
#
#   student  Instant Teacher  com.yaronj.student
#   teacher  Pro Teacher      com.yaronj.tim
#
# Before archiving, the build number (CURRENT_PROJECT_VERSION) goes up by one.
# App Store Connect refuses a build number it has already seen for a version,
# so every run gets a new one. The number lives in the four app build
# configurations in Darwin/TeacherMinute.xcodeproj; they override Skip.env, so
# that file is left alone, and so is the UI-test target. Both apps get the same
# number. The bump stays in the working tree for you to commit.
#
# Signing is automatic with team 5WRH6356JL. xcodebuild talks to Apple with an
# App Store Connect API key when these are set (put them in ~/.zshrc):
#
#   ASC_KEY_PATH   the AuthKey_<id>.p8 file, kept outside the repo
#   ASC_KEY_ID     its Key ID
#   ASC_ISSUER_ID  the Issuer ID shown above the keys list
#
# (App Store Connect → Users and Access → Integrations → Team Keys, role App
# Manager or Admin). Without them it falls back to the Apple account signed in
# to Xcode (Settings → Accounts), whose sign-in expires every so often and then
# fails the upload with "missing Xcode-Token".
#
# UPLOAD=0 exports the .ipa files into build/ios-archives instead of uploading.
# The Android build is switched off for the archive (SKIP_ACTION=none).

# The body sits in one { } block, so bash reads the whole file before it
# runs any of it: editing the script during a run cannot break that run.
{
set -euo pipefail

START=$(date +%s)
# Progress line with the clock time and the minutes since this script started.
say() { echo "[$(date +%H:%M:%S) +$(( ($(date +%s) - START) / 60 ))m] $*"; }

WHICH="${1:-both}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/Darwin/TeacherMinute.xcodeproj/project.pbxproj"
EXPORT_OPTIONS="$ROOT/Darwin/ExportOptions.plist"
OUT="$ROOT/build/ios-archives"

case "$WHICH" in
  both)    SCHEMES=("Instant Teacher" "Pro Teacher") ;;
  student) SCHEMES=("Instant Teacher") ;;
  teacher) SCHEMES=("Pro Teacher") ;;
  *) echo "usage: $0 [both|student|teacher]" >&2; exit 2 ;;
esac

# Sign in to Apple with the API key when one is configured; check it before
# the build number moves.
AUTH=()
if [[ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]]; then
  [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]] \
    || { echo "set all three of ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, or none" >&2; exit 1; }
  [[ -f "$ASC_KEY_PATH" ]] || { echo "ASC_KEY_PATH points to $ASC_KEY_PATH, which does not exist" >&2; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# 1. Bump the build number of the app configurations.
say "iOS: started $(date '+%Y-%m-%d %H:%M')"
BUMP="$(mktemp -t archive-ios)"
python3 - "$PBXPROJ" > "$BUMP" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
APPS = ("com.yaronj.student", "com.yaronj.tim")

def app_config(i):
    # The bundle id sits in the same buildSettings block, after the build number.
    for line in lines[i + 1:]:
        if re.match(r"\s*name = ", line):
            return None
        m = re.match(r"\s*PRODUCT_BUNDLE_IDENTIFIER = (\S+);", line)
        if m:
            return m.group(1) if m.group(1) in APPS else None
    return None

targets = [i for i, l in enumerate(lines)
           if re.match(r"\s*CURRENT_PROJECT_VERSION = \d+;", l) and app_config(i)]
if len(targets) != 4:
    sys.exit(f"expected 4 app build configurations, found {len(targets)}")
current = max(int(re.search(r"\d+", lines[i]).group()) for i in targets)
new = current + 1
for i in targets:
    lines[i] = re.sub(r"\d+", str(new), lines[i], count=1)
open(path, "w", encoding="utf-8").write("\n".join(lines))

versions = {re.search(r"MARKETING_VERSION = (\S+);", l).group(1)
            for l in lines if "MARKETING_VERSION" in l and "1.0;" not in l}
print(current, new, ",".join(sorted(versions)))
PY
read -r OLD NEW VERSION < "$BUMP"; rm -f "$BUMP"
say "iOS: build number $OLD → $NEW (version $VERSION)"
if [[ ${#AUTH[@]} -gt 0 ]]; then say "iOS: signing in to Apple with API key $ASC_KEY_ID"
else say "iOS: signing in to Apple with the account in Xcode (no ASC_KEY_* set)"; fi

# 2. Archive and export (or upload) each app.
mkdir -p "$OUT"
OPTIONS="$EXPORT_OPTIONS"
if [[ "${UPLOAD:-1}" == "0" ]]; then
  OPTIONS="$OUT/ExportOptions-local.plist"
  cp "$EXPORT_OPTIONS" "$OPTIONS"
  plutil -replace destination -string export "$OPTIONS"
fi

cd "$ROOT"
for scheme in "${SCHEMES[@]}"; do
  name="${scheme// /}"
  archive="$OUT/$name-$VERSION-$NEW.xcarchive"
  say "iOS: $scheme archiving (log: $OUT/$name-archive.log)…"
  xcodebuild archive -workspace Project.xcworkspace -scheme "$scheme" \
    -destination "generic/platform=iOS" -archivePath "$archive" \
    -skipMacroValidation -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} SKIP_ACTION=none \
    > "$OUT/$name-archive.log" 2>&1 \
    || { say "iOS: $scheme archive FAILED; see $OUT/$name-archive.log" >&2; exit 1; }
  say "iOS: $scheme archive complete"
  if [[ "${UPLOAD:-1}" == "0" ]]; then say "iOS: $scheme exporting…"; else say "iOS: $scheme uploading to App Store Connect…"; fi
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$OPTIONS" \
    -exportPath "$OUT/$name-$VERSION-$NEW" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
    > "$OUT/$name-export.log" 2>&1 \
    || { say "iOS: $scheme export/upload FAILED; see $OUT/$name-export.log" >&2; exit 1; }
  if [[ "${UPLOAD:-1}" == "0" ]]; then say "iOS: $scheme exported"; else say "iOS: $scheme uploaded"; fi
done

if [[ "${UPLOAD:-1}" == "0" ]]; then
  say "iOS: done, exported $VERSION ($NEW) to $OUT; nothing was uploaded."
else
  say "iOS: done, uploaded $VERSION ($NEW); it appears in TestFlight once App Store Connect has processed it."
fi
echo "Commit the build number bump in $PBXPROJ."
exit
}
