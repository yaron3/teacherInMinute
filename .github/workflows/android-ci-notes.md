# Android CI: what is known

Notes for `android.yml`, from fifteen runs on 2026-09-22. **Runs 14 and 15 both
passed**, end to end, on the same tree — including the dex assertion. That meets
the two-green bar for wiring the job into pull requests; whether to pay the
runtime for that is a judgement call, not a technical one.

Start here before touching the workflow again. Most of what follows is a record
of what was wrong with the *environment*, not with this repository's code — the
same build succeeded on a developer Mac throughout.

## What a green run looks like

Runs 14 and 15, both on `82eefc1`:

| Step | Run 14 | Run 15 |
|---|---|---|
| Set up Skip | 3m39s | 3m22s |
| Build the Android app | **34m43s** | **33m22s** |
| Verify the Application class reached the APK | pass | pass |

That last step is the assertion the job exists for. It runs under
`set -euo pipefail` and exits 1 unless `grep -qa 'teacher/minute/AndroidAppMain'`
matches the dex, so the step passing *is* the proof that the Application class
reached the APK. A green `assembleDebug` alone never was: that is exactly what
shipped an APK with no Application class and a ClassNotFoundException at launch.

**Budget ~35-40 minutes.** Before the Swift-for-Android compile worked, every
run died inside 21 minutes, so the earlier timings in this file are timings of
failures, not of the work.

## Settled facts

**The runner is not missing anything.** `macos-latest` ships the Android SDK at
`/Users/runner/Library/Android/sdk` with `build-tools`, `cmake`, `platforms`,
`platform-tools` and three NDKs: `27.3.13750724`, `28.2.13676358`,
`29.0.14206865`. `skip doctor` passes every check. The
`android-actions/setup-android` step is therefore **redundant** and can be
deleted; it is still in the workflow only because removing it at the same time
as a real fix would make the next result unattributable.

**`ANDROID_NDK_ROOT` is set to the empty string, not unset.** `setup-skip`
finishes with `echo "ANDROID_NDK_ROOT=" >> $GITHUB_ENV`, working around
[finagolfin/swift-android-sdk#207]. A diagnostic using `${VAR+set}` confirms it:

```
--- ANDROID_NDK_ROOT defined? ---
defined=yes
```

Anything testing whether the variable is *defined*, rather than whether it holds
a value, takes `""` as the NDK path. That is why a machine holding three NDKs
reported having none.

**Confirmed in run 10, and fixed.** The workflow restores the value through
`$GITHUB_ENV` in its own step, and the build runs `--no-daemon`. Both parts
matter: a Gradle daemon keeps the environment of the JVM it started in, and
`setup-skip` pulls in `gradle/actions/setup-gradle`, so a daemon can already be
up holding the empty value — which is why run 8's in-step `export` changed
nothing. Run 10 ends with

```
ANDROID_NDK_ROOT=/Users/runner/Library/Android/sdk/ndk/27.3.13750724
```

and the NDK error is absent from the log. Setting the variable did **not**
trigger [finagolfin/swift-android-sdk#207], the bug the empty export exists to
avoid.

**It is not an NDK version mismatch.** The Swift SDK carries its own sysroot and
names no external NDK. Every target in
`~/.swiftpm/swift-sdks/swift-6.4.0-RELEASE_android.artifactbundle/swift-android/swift-sdk.json`
reads:

```json
"sdkRootPath": "ndk-sysroot",
"toolsetPaths": [ "swift-toolset.json" ]
```

`sdkRootPath` is relative to the bundle. A scan of those files for absolute NDK
paths returned nothing.

**The `SkipFirebaseCore` error is specific to Swift 6.4.** The `swift` on the
runner's PATH is 6.3.3, the same as a local machine where this builds. 6.4.0
exists only as `~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain`,
installed alongside the Swift SDK for Android by `skip android sdk install`, and
the Android build invokes it by absolute path. `setup-skip`'s `swift-version`
input does **not** control this — it only runs `swiftly install` and never
selects the toolchain, and it is skipped entirely when empty. The lever is
`swift-android-sdk-version`, whose valid values were never established.

## What made it pass

Four environment problems, cleared in this order. Task counts are a usable
progress signal: 552 → 567 → 599 → 617 → green.

1. **`setup-android` asked for a retired package.** Its `packages` input
   defaults to `tools platform-tools`, and `tools` no longer exists, so
   `sdkmanager` exits 1. Pinned to `platform-tools`.
2. **`gradle-wrapper.jar` was missing from the repository.** See below.
3. **`ANDROID_NDK_ROOT` was the empty string.** See above.
4. **Swift 6.4 rejected the package graph.** Unpinned, `skip android sdk
   install` brings 6.4.0, which fails with `SkipFirebaseCore ... cannot be built
   dynamically because there is a package product with the same name`. Pinning
   `swift-android-sdk-version` fixed it — but the version must have **three
   parts**. `'6.3'` is accepted and installs a `swift-6.3-RELEASE` SDK next to a
   `swift-6.3.3-RELEASE` host toolchain, and a `.swiftmodule` records the exact
   compiler that produced it:

   ```
   error: module compiled with Swift 6.3 cannot be imported by the
   Swift 6.3.3 compiler: .../Swift.swiftmodule/...
   ```

   `'6.3.3'` matches SDK, host toolchain and the `swift` on PATH, and builds.
   Unpinned 6.4.0 matched on both sides only by accident.

## Still worth doing

- **Uncomment the `pull_request` trigger.** The two-green bar is met, so this
  is now purely a cost decision: ~35 minutes of macOS runner time per pull
  request touching `teacher-minute/**`.
- **Delete the `setup-android` step.** It is redundant (see above); it was kept
  only so that removing it would not confuse attribution while something else
  was being fixed.
- **Watch the Swift pin.** `'6.3.3'` freezes CI against a toolchain that will
  age. When it moves, both halves have to move together.

One thing remains unexplained: the same generated `build.gradle.kts` is
registered under two Gradle projects, `:skipstone:TeacherMinute` and
`:TeacherMinute`, and both run `swift build` against the same scratch path. In
runs 3 to 9 the two failed in *different* ways, which is what a race looks like;
from run 10 on they behaved identically. Whether this duplication is normal for
Skip is unknown.

## Reading the logs is the bottleneck

Budget for this; it cost more than the debugging did.

- GitHub serves job logs **only after the whole job finishes**. Putting a
  diagnostic step early buys nothing for a reader using the API — though it is
  visible live in a browser.
- The API returns at most the **last 5000 lines**. A full build overruns that,
  so anything printed at the *start* of the build step is unreachable. The build
  step therefore prints the environment at its **end**.
- The direct log download URL is on `productionresultssa14.blob.core.windows.net`,
  which some environments' egress policy blocks outright.
- `--stacktrace` was dropped. Across six failing runs it added hundreds of lines
  of Gradle internals per failure and never said anything the error line above
  it had not.

Hence the `diagnostics-only` dispatch input: it sets up the toolchain, prints
the report and stops, in about five minutes with a log short enough to read
whole. Use it for any question about the runner's environment.

## Fixed along the way

Two real defects, both already on `master` or on the branch:

- `android-actions/setup-android@v3` defaults `packages` to `tools platform-tools`.
  `tools` is the retired SDK Tools package Google removed from the repository, so
  `sdkmanager` exits 1 and the action crashes. Pinned to `platform-tools`.
- **`gradle/wrapper/gradle-wrapper.jar` was never committed.** `gradlew`,
  `gradlew.bat` and `gradle-wrapper.properties` were all present; the jar the
  launcher executes was not, and no `.gitignore` rule excluded it. A fresh clone
  could not run `./gradlew` at all. It went unnoticed because the Xcode build
  goes through `skip gradle`, which brings its own Gradle — this job was the
  first thing in the project to invoke the wrapper. Added at Gradle 9.5.0,
  matching `distributionUrl`, checksum verified against
  <https://gradle.org/release-checksums/>.

## Two guesses that were wrong

Recorded so they are not repeated.

- **Reordering `setup-android` before `setup-skip`**, on the theory that
  `skip android sdk install` needed an existing SDK root to place the NDK into.
  Run 4 failed identically. The NDK was never missing.
- **Exporting `ANDROID_NDK_ROOT` inside the build step.** Run 8 failed
  identically, and whether the value even reached the compiler could not be
  determined, because the echo was at the start of a step whose output overran
  the readable window.

[finagolfin/swift-android-sdk#207]: https://github.com/finagolfin/swift-android-sdk/issues/207
