# Debug-build Firebase config

Put the staging project's `google-services.json` in this directory and debug
builds will use it; release builds keep the production one in `app/`.

Nothing in `build.gradle.kts` selects it. The Google Services plugin looks for
`src/<buildType>/google-services.json` before falling back to
`app/google-services.json`, so the file's location is the whole mechanism.

Product flavors would be the more usual way to do this, and they are the wrong
way here: Xcode's "Run skip gradle" phase calls
`skip gradle -p ../Android ${SKIP_ACTION}${CONFIGURATION}`, which resolves to
task names like `launchDebug`. Adding a flavor renames those to
`launchProdDebug` and the build phase stops finding them.

See `STAGING.md` at the repository root.
