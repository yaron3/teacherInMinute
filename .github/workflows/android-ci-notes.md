# Android CI: what is known

Notes for `android.yml`, written after ten runs on 2026-09-22. The job is
**manual only** (`workflow_dispatch`) and **has never passed**, though run 10
got down to a single remaining failure. It is kept
because what it has already found is worth more than its current red status
costs — nothing depends on it, so nothing is blocked by it.

Start here before touching the workflow again.

## Where it stops

As of run 10, **one** failure remains. Gradle configures, resolves, compiles the
app module's Kotlin and runs 599 tasks over roughly 19 minutes, and both Swift
tasks then fail on the same thing:

```
error: Swift package target 'SkipFirebaseCore' is linked as a static library by
       'TeacherMinute-product' and 8 other targets, but cannot be built
       dynamically because there is a package product with the same name.
  > Task :TeacherMinute:buildAndroidSwiftPackageDebug FAILED
  > Task :skipstone:TeacherMinute:buildAndroidSwiftPackageDebug FAILED
```

It is an environment problem, not a defect in this repository's code: the same
build succeeds on a developer Mac. See "The one remaining failure" below.

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

## The one remaining failure, and where to resume

`SkipFirebaseCore` cannot be built dynamically because a package product shares
its name. Nothing in this repository is wrong: the toolchain differs.

The next thing to try is pinning `swift-android-sdk-version` on `setup-skip` to
a 6.3 SDK, so CI compiles with the toolchain that works locally. A wrong version
string fails during setup after about three minutes rather than eighteen, so it
is cheap to probe — and the valid values were never established, which is the
first thing to find out.

Two observations worth carrying in, both unexplained:

- The same generated `build.gradle.kts` is registered under two Gradle projects,
  `:skipstone:TeacherMinute` and `:TeacherMinute`, and both run `swift build`
  against the same scratch path. In runs 3 to 9 the two failed in *different*
  ways, which is what a race looks like; in run 10 they failed identically.
  Whether this duplication is normal for Skip is unknown.
- Task counts rose 552 → 567 → 599 as each environment problem was cleared, so
  the count is a decent progress signal across runs.

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
