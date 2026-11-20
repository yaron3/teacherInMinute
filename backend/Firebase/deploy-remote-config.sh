#!/bin/bash
# Deploys remote_config_tim.json to a Firebase project.
#
#   ./deploy-remote-config.sh staging      (or prod, or a project id)
#
# The template's conditions name apps by their production app ids
# (app.id == '1:922632930084:ios:…'), and Remote Config refuses a template
# naming apps another project does not have. For any project but production,
# each production app id is replaced by the target project's app with the same
# bundle id or package name before the upload. A production app the target has
# no counterpart for is replaced by the target's web app, which no phone ever
# matches, so its condition stays as dead there as the app is.
#
# The template's user-property conditions also need the property registered in
# the target's Analytics (Custom definitions, user scope): user_language.
set -euo pipefail

cd "$(dirname "$0")"
PROD_PROJECT="teacher-in-a-moment"
FIREBASE=(npx --prefix functions firebase)

case "${1:-}" in
  prod) PROJECT="$PROD_PROJECT" ;;
  staging) PROJECT="teacher-in-a-moment-staging" ;;
  "") echo "usage: $0 staging|prod|<project-id>" >&2; exit 64 ;;
  *) PROJECT="$1" ;;
esac

if [[ "$PROJECT" == "$PROD_PROJECT" ]]; then
  exec "${FIREBASE[@]}" deploy --project "$PROJECT" --only remoteconfig
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"${FIREBASE[@]}" apps:list --project "$PROD_PROJECT" --json > "$WORK/prod-apps.json"
"${FIREBASE[@]}" apps:list --project "$PROJECT" --json > "$WORK/target-apps.json"

python3 - "$WORK" <<'PY'
import json, re, sys

work = sys.argv[1]
def apps(name):
    return json.load(open(f"{work}/{name}"))["result"]

prod, target = apps("prod-apps.json"), apps("target-apps.json")
by_key = {(a["platform"], a.get("namespace")): a["appId"] for a in target}
web = next((a["appId"] for a in target if a["platform"] == "WEB"), None)

mapping = {}
for app in prod:
    key = (app["platform"], app.get("namespace"))
    if key in by_key:
        mapping[app["appId"]] = by_key[key]
    elif web:
        mapping[app["appId"]] = web
        print(f"  no {key[0]} app {key[1]} in the target; its conditions point at the web app")
    else:
        mapping[app["appId"]] = None

template = open("remote_config_tim.json").read()
def swap(match):
    app_id = match.group(0)
    new = mapping.get(app_id)
    if new is None:
        sys.exit(f"no counterpart for {app_id} in the target project, and no web app to stand in")
    return new
template = re.sub(r"1:\d+:(?:ios|android|web):[0-9a-f]+", swap, template)
open(f"{work}/remote_config.json", "w").write(template)
json.dump({"remoteconfig": {"template": "remote_config.json"}}, open(f"{work}/firebase.json", "w"))
PY

# Run from the work folder: the CLI resolves the template against the working
# directory, not the config file's.
FUNCTIONS_DIR="$PWD/functions"
cd "$WORK"
npx --prefix "$FUNCTIONS_DIR" firebase deploy --config firebase.json --project "$PROJECT" --only remoteconfig
