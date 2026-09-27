# TeacherMinute

This is a [Skip](https://skip.dev) dual-platform app project.

## Two apps

The project builds two apps from the same sources, one per role:

| App | For | Xcode target and scheme | Android flavor | Bundle id and application id |
| --- | --- | --- | --- | --- |
| Instant Teacher | Students | `Instant Teacher` | `student` | `com.yaronj.student` |
| Pro Teacher | Teachers | `Pro Teacher` | `teacher` | `com.yaronj.teacher` |

Nobody picks a role when signing up: each app is built for one, which it reads
at runtime (`AppRole.swift`) from `TIM_APP_ROLE` in its Xcode target or
`BuildConfig.APP_ROLE` in its flavor. Signing in to one app with an account of
the other role names the right app and signs back out.

Each app is its own Firebase app. `Darwin/InstantTeacher/` and
`Darwin/ProTeacher/` each hold that app's `GoogleService-Info.plist`, and
`Android/app/google-services.json` lists both packages. A target's
`TIM_GOOGLE_URL_SCHEME` build setting has to be the `REVERSED_CLIENT_ID` from
its plist; the build fails with a note saying so when it is not.


<!-- TODO: add iOS screenshots to fastlane metadata
## iPhone Screenshots

<img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/1_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/2_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/3_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/4_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/5_en-US.png" style="width: 18%" />
-->

<!-- TODO: add Android screenshots to fastlane metadata
## Android Screenshots

<img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/1_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/2_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/3_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/4_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/5_en-US.png" style="width: 18%" />
-->

## Building

This project is both a stand-alone Swift Package Manager module,
as well as an Xcode project that builds and translates the project
into a Kotlin Gradle project for Android using the skipstone plugin.

### Google Play signing

Create a local upload keystore before building a Play release:

```sh
keytool -genkeypair \
    -v \
    -keystore Android/app/keystore.jks \
    -storetype JKS \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias upload
cp Android/app/keystore.properties.example Android/app/keystore.properties
```

Edit `Android/app/keystore.properties` with the passwords used for the upload
key, then build the signed Android App Bundles by running the Gradle task
`:app:bundleRelease` from Android Studio, or `:app:bundleStudentRelease` /
`:app:bundleTeacherRelease` for one app.

The signed bundles are created at `.build/Android/app/outputs/bundle/`, in
`studentRelease/` (Instant Teacher) and `teacherRelease/` (Pro Teacher).
`keystore.jks` and `keystore.properties` are intentionally ignored by Git.

## Running

Xcode and Android Studio must be downloaded and installed in order to
run the app in the iOS simulator / Android emulator.
An Android emulator must already be running, which can be launched from
Android Studio's Device Manager.

The project can be opened and run in Xcode from
`Project.xcworkspace`, which also enabled parallel
development of any Skip libary dependencies.

To run both the Swift and Kotlin versions of an app simultaneously,
launch its target from Xcode: "Instant Teacher" or "Pro Teacher".
A build phase runs the "Run skip gradle" script that
will deploy the same app's Android flavor to a running Android emulator or
connected device, through the Gradle task `launchStudentDebug` or
`launchTeacherDebug`.
Logging output for the iOS app can be viewed in the Xcode console, and in
Android Studio's logcat tab for the transpiled Kotlin app, or
using `adb logcat` from a terminal.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.
