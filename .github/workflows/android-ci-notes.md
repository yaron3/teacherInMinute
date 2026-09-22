# Android CI: what is known

Notes for `android.yml`, written after ten runs on 2026-09-22. The job is
**manual only** (`workflow_dispatch`) and **has never passed**. It is kept
because what it has already found is worth more than its current red status
costs — nothing depends on it, so nothing is blocked by it.

Start here before touching the workflow again.

## Where it stops

The job now gets all the way into the build. Gradle configures, resolves,
compiles the app module's Kotlin, and runs ~550 tasks over roughly 16 minutes
before two failures in the Swift-for-Android stage:

```
error: No Android NDK is installed at any of the standard locations
  > Task :skipstone:TeacherMinute:buildAndroidSwiftPackageDebug FAILED

error: Swift package target 'SkipFirebaseCore' is linked as a static library by
       'TeacherMinute-product' and 8 other targets, but cannot be built
       dynamically because there is a package product with the same name.
  > Task :TeacherMinute:buildAndroidSwiftPackageDebug FAILED
```

Both are environment problems, not defects in this repository's code. The same
build succeeds on a developer Mac.

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
a value, takes `""` as the NDK path. That is the most likely reading of the "no
NDK at any standard location" message on a machine holding three of them, and it
is the hypothesis the workflow currently acts on. **It is not yet confirmed.**

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

## Unverified, and where to resume

Run 10 (`073c144`) was in flight when this work stopped, testing one change:
`ANDROID_NDK_ROOT` set through `$GITHUB_ENV` in its own step rather than
exported inside the build step, plus `--no-daemon`.

The reasoning: a Gradle daemon keeps the environment of the JVM it started in.
`setup-skip` pulls in `gradle/actions/setup-gradle`, so a daemon may already be
running with the empty value by the time the build step executes, which would
make an in-step `export` invisible to the compiler. Run 8 exported it in-step
and changed nothing — consistent with that, though not proof, because the
evidence could not be read (see below).

**Its result is in the Actions tab and has not been looked at.** That is the
first thing to check.

If the NDK error is gone, only the Swift 6.4 `SkipFirebaseCore` failure remains,
and the next thing to try is pinning `swift-android-sdk-version` on `setup-skip`
to a 6.3 SDK — a wrong version string fails in setup after ~3 minutes rather
than ~18, so it is cheap to probe.

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
