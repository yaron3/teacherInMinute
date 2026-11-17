# Debug-build sources

`google-services.json` in this directory, and in `../release/`, is copied there
by `app/build.gradle.kts` on every build from `teacher-minute/Config/<project>/`
and is gitignored. Edit the file under `Config/`, and pick which project each
build type uses in `Config/Environment.xcconfig`.

The copy lands here because the Google Services plugin has no setting for its
file's location: it reads `src/<buildType>/google-services.json` first.

Staging is not a product flavor. The flavors are the two apps, student and
teacher, and Xcode's "Run skip gradle" phase names one of them in every task it
runs (`launchStudentDebug`, `launchTeacherDebug`). A second flavor dimension
would rename those again, to `launchStudentStagingDebug` and the like, and the
build phase would stop finding them.

See `STAGING.md` at the repository root.
