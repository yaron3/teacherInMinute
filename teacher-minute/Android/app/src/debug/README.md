# Debug-build Firebase config

Put the staging project's `google-services.json` in this directory and debug
builds of both apps will use it; release builds keep the production one in
`app/`. The file has to list both packages, `com.yaronj.student` and
`com.yaronj.teacher`, so register both apps in the staging project before
downloading it.

Nothing in `build.gradle.kts` selects it. The Google Services plugin looks for
`src/<buildType>/google-services.json` before falling back to
`app/google-services.json`, flavors or not, so the file's location is the
whole mechanism.

Staging is not a product flavor. The flavors are the two apps, student and
teacher, and Xcode's "Run skip gradle" phase names one of them in every task it
runs (`launchStudentDebug`, `launchTeacherDebug`). A second flavor dimension
would rename those again, to `launchStudentStagingDebug` and the like, and the
build phase would stop finding them.

See `STAGING.md` at the repository root.
