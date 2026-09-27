import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import java.io.ByteArrayOutputStream
import java.util.Properties
import javax.inject.Inject

plugins {
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.android.application)
    id("skip-build-plugin")
    id("com.google.gms.google-services") version "4.4.4"
    id("com.google.firebase.crashlytics") version "3.0.6"
}

// No Kotlin Android plugin: Android Gradle Plugin 9, which Skip 1.9 builds
// with, compiles Kotlin itself and refuses to apply that plugin. Its built-in
// Kotlin support is what compiles the hand-written files in app/src/main/kotlin,
// among them Main.kt, which declares the teacher.minute.AndroidAppMain that the
// manifest names as the Application class. If that compilation ever goes
// missing, the build still succeeds and the app dies at launch on a
// ClassNotFoundException, which is why the Android CI job checks that
// AndroidAppMain reached the APK.

skip {
}

val keystorePropertiesFile = file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun signingValue(propertyName: String, environmentName: String): String? {
    return keystoreProperties.getProperty(propertyName)
        ?: System.getenv(environmentName)
}

val releaseStoreFile = signingValue("storeFile", "TEACHER_MINUTE_UPLOAD_STORE_FILE")
val releaseKeyAlias = signingValue("keyAlias", "TEACHER_MINUTE_UPLOAD_KEY_ALIAS")
val releaseStorePassword = signingValue("storePassword", "TEACHER_MINUTE_UPLOAD_STORE_PASSWORD")
val releaseKeyPassword = signingValue("keyPassword", "TEACHER_MINUTE_UPLOAD_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseKeyAlias,
    releaseStorePassword,
    releaseKeyPassword
).all { !it.isNullOrBlank() }

val generatedManifestEntriesToRemove = listOf(
    "com.google.android.gms.permission.AD_ID",
    "android.permission.ACCESS_ADSERVICES_AD_ID",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
    "androidx.work.impl.foreground.SystemForegroundService"
)

fun generatedManifestSearchRoots(): List<File> {
    return listOf(
        layout.buildDirectory.get().asFile,
        file("build"),
        file("intermediates"),
        file("outputs")
    ).distinctBy { it.absolutePath }
        .filter { it.exists() }
}

fun generatedAndroidManifests(): Sequence<File> {
    return generatedManifestSearchRoots()
        .asSequence()
        .flatMap { root -> root.walkTopDown().asSequence() }
        .filter { file -> file.isFile && file.name == "AndroidManifest.xml" }
}

fun stripForegroundServiceEntriesFromGeneratedManifests() {
    val permissionElements = generatedManifestEntriesToRemove
        .filter { entry -> entry.contains(".permission.") }
        .map { permission ->
            Regex("""\s*<uses-permission(?:-sdk-23)?\s+[^>]*android:name="$permission"[^>]*/>\s*""")
        }
    val workManagerForegroundServiceElement = Regex(
        """\s*<service\b[^>]*android:name="androidx\.work\.impl\.foreground\.SystemForegroundService"[^>]*(?:/>\s*|>.*?</service>\s*)""",
        setOf(RegexOption.DOT_MATCHES_ALL)
    )

    generatedAndroidManifests()
        .forEach { manifest ->
            val original = manifest.readText()
            var stripped = original
            permissionElements.forEach { permissionElement ->
                stripped = stripped.replace(permissionElement, "\n")
            }
            stripped = stripped.replace(workManagerForegroundServiceElement, "\n")
            if (stripped != original) {
                manifest.writeText(stripped)
                logger.lifecycle("Removed foreground service manifest entries from ${manifest.relativeTo(projectDir)}")
            }
        }
}

fun verifyNoForegroundServiceEntriesInGeneratedManifests() {
    val offenders = generatedAndroidManifests()
        .filter { manifest ->
            val text = manifest.readText()
            generatedManifestEntriesToRemove.any { entry -> text.contains(entry) }
        }
        .map { manifest -> manifest.relativeTo(projectDir).path }
        .toList()

    if (offenders.isNotEmpty()) {
        throw GradleException(
            "Generated manifest still contains foreground service entries: ${offenders.joinToString()}"
        )
    }
}

// Kotlin's bytecode level, kept equal to the Java source and target
// compatibility set in android { compileOptions } below — the two halves of the
// module have to agree. Configured on the compile tasks rather than through a
// `kotlin { }` block, at the top level or inside android { }, because both of
// those are extension accessors the Kotlin DSL generates from an applied
// Kotlin plugin, and this script applies none (see above), so naming either one
// fails script compilation. The task type comes from the Kotlin Gradle plugin
// on the buildscript classpath, which needs no accessor.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get())
    }
}

android {
    namespace = group as String
    compileSdk = libs.versions.android.sdk.compile.get().toInt()
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
    }
    packaging {
        jniLibs {
            keepDebugSymbols.add("**/*.so")
            pickFirsts.add("**/*.so")
            // this option will compress JNI .so files
            useLegacyPackaging = true
        }
    }

    defaultConfig {
        minSdk = libs.versions.android.sdk.min.get().toInt()
        targetSdk = libs.versions.android.sdk.compile.get().toInt()
        // skip.tools.skip-build-plugin will automatically use Skip.env properties for:
        // applicationId = ANDROID_APPLICATION_ID ?? PRODUCT_BUNDLE_IDENTIFIER
        // versionCode = CURRENT_PROJECT_VERSION
        // versionName = MARKETING_VERSION
    }

    // Two apps from one codebase, the same pair as the Xcode targets: Instant
    // Teacher for students and Pro Teacher for teachers. Each flavor has its
    // own applicationId (replacing the one Skip sets from Skip.env), its own
    // name (src/<flavor>/res/values/strings.xml) and Firebase app, and tells the
    // shared Swift code which role it serves through BuildConfig.APP_ROLE — see
    // AndroidAppRole.kt and AppRole.swift.
    //
    // appUrlScheme is the custom scheme in AndroidManifest.xml. Instant Teacher
    // keeps "teacherminute", which the backend's card-payment return links
    // open; Pro Teacher takes another, so those links have only one app to
    // open when both are installed.
    //
    // unstrippedNativeLibsDir is where the Crashlytics upload finds the .so
    // files as Swift produced them, before AGP strips them. The path names the
    // variant, so each flavor gives its own; the release build type below turns
    // the upload on.
    flavorDimensions += "app"
    productFlavors {
        create("student") {
            dimension = "app"
            applicationId = "com.yaronj.student"
            buildConfigField("String", "APP_ROLE", "\"student\"")
            manifestPlaceholders["appUrlScheme"] = "teacherminute"
            configure<CrashlyticsExtension> {
                unstrippedNativeLibsDir = layout.buildDirectory.dir(
                    "intermediates/merged_native_libs/studentRelease/mergeStudentReleaseNativeLibs/out/lib"
                )
            }
        }
        create("teacher") {
            dimension = "app"
            applicationId = "com.yaronj.teacher"
            buildConfigField("String", "APP_ROLE", "\"teacher\"")
            manifestPlaceholders["appUrlScheme"] = "proteacher"
            configure<CrashlyticsExtension> {
                unstrippedNativeLibsDir = layout.buildDirectory.dir(
                    "intermediates/merged_native_libs/teacherRelease/mergeTeacherReleaseNativeLibs/out/lib"
                )
            }
        }
    }

    buildFeatures {
        buildConfig = true
    }

    lint {
        disable.add("Instantiatable")
        disable.add("MissingPermission")
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs.
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles.
        includeInBundle = false
    }

    // Release signing uses app/keystore.properties or matching environment variables.
    // See keystore.properties.example for the local Google Play upload key format.
    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
            } else {
                // Keep debug builds/configuration working, but fail release tasks below.
                keyAlias = signingConfigs.getByName("debug").keyAlias
                keyPassword = signingConfigs.getByName("debug").keyPassword
                storeFile = signingConfigs.getByName("debug").storeFile
                storePassword = signingConfigs.getByName("debug").storePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false // can be set to true for debugging release build, but needs to be false when uploading to store
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
            // Turns the raw addresses in a native crash report back into Swift
            // frames. The upload is a separate task per app, so a release build
            // stays offline unless you ask for it:
            //   ./gradlew :app:assembleStudentRelease :app:uploadCrashlyticsSymbolFileStudentRelease
            //   ./gradlew :app:assembleTeacherRelease :app:uploadCrashlyticsSymbolFileTeacherRelease
            // Each flavor above says where its libraries are.
            configure<CrashlyticsExtension> {
                nativeSymbolUploadEnabled = true
            }
            // proguard-android-optimize.txt rather than proguard-android.txt:
            // the two differ by the latter's -dontoptimize, and AGP 9 drops the
            // non-optimizing file, which `skip gradle` warns about by name.
            // R8 already ran here — isMinifyEnabled shrinks and obfuscates
            // either way — so what this turns on is the optimization pass:
            // inlining, dead-branch removal, class merging. proguard-rules.pro
            // keeps teacher.minute.**, skip.**, tools.skip.** and the JNA and
            // bridge classes whole, which is everything reached reflectively or
            // over JNI, so optimization has nothing load-bearing to rewrite.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Installs and starts one app on every connected device, or only on
// ANDROID_SERIAL's, as Skip's own launch task does.
abstract class LaunchAppTask : DefaultTask() {
    @get:Inject abstract val execOperations: ExecOperations

    /** The activity to start, as `applicationId/fully.qualified.Activity`. */
    @get:Input abstract val component: Property<String>

    @get:Internal abstract val adb: RegularFileProperty

    @TaskAction
    fun launch() {
        val adbPath = adb.get().asFile.absolutePath
        val devicesOutput = ByteArrayOutputStream()
        execOperations.exec {
            commandLine(adbPath, "devices")
            standardOutput = devicesOutput
        }
        val requestedSerial = System.getenv("ANDROID_SERIAL").orEmpty()
        val serials = devicesOutput.toString("UTF-8").lines()
            .filter { it.endsWith("\tdevice") }
            .map { it.substringBefore('\t') }
            .filter { requestedSerial.isEmpty() || it == requestedSerial }
        if (serials.isEmpty()) {
            throw GradleException("No connected Android devices or emulators were reported by `adb devices`.")
        }
        serials.forEach { serial ->
            execOperations.exec {
                commandLine(
                    adbPath, "-s", serial, "shell", "am", "start",
                    "-a", "android.intent.action.MAIN",
                    "-c", "android.intent.category.LAUNCHER",
                    "-n", component.get()
                )
            }
        }
    }
}

// Skip's launchDebug and launchRelease serve a single app: they depend on
// installDebug, which the flavors replace with one install task per app, and
// start the activity under Skip.env's identifier. These are the per-app
// versions — launchStudentDebug, launchTeacherRelease and so on — which the
// Xcode "Run skip gradle" phase calls for the target being built.
androidComponents {
    onVariants { variant ->
        val variantName = variant.name.replaceFirstChar { it.uppercase() }
        tasks.register<LaunchAppTask>("launch$variantName") {
            group = "install"
            description = "Installs and starts the ${variant.name} app on the connected devices."
            dependsOn("checkDevices", "install$variantName")
            component.set(variant.applicationId.zip(variant.namespace) { id, namespace ->
                "$id/$namespace.MainActivity"
            })
            adb.set(sdkComponents.adb)
        }
    }
}

// Skip's own tasks cannot tell which app to launch. Rather than failing on a
// missing installDebug, say what to run instead.
tasks.configureEach {
    val buildType = when (name) {
        "launchDebug" -> "Debug"
        "launchRelease" -> "Release"
        else -> return@configureEach
    }
    setDependsOn(emptyList<Any>())
    actions.clear()
    doFirst {
        throw GradleException(
            "There are two apps: run launchStudent$buildType (Instant Teacher) " +
                "or launchTeacher$buildType (Pro Teacher)."
        )
    }
}

gradle.taskGraph.whenReady {
    val isReleaseBuild = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }

    if (isReleaseBuild && !hasReleaseSigning) {
        throw GradleException(
            """
            Google Play release signing is not configured.

            Create Android/app/keystore.properties from keystore.properties.example,
            or provide these environment variables:
            TEACHER_MINUTE_UPLOAD_STORE_FILE
            TEACHER_MINUTE_UPLOAD_KEY_ALIAS
            TEACHER_MINUTE_UPLOAD_STORE_PASSWORD
            TEACHER_MINUTE_UPLOAD_KEY_PASSWORD
            """.trimIndent()
        )
    }
}

tasks.configureEach {
    if (name.contains("Manifest", ignoreCase = true)) {
        doLast("stripForegroundServiceEntries") {
            stripForegroundServiceEntriesFromGeneratedManifests()
        }
    }

    if (name.contains("Release", ignoreCase = true) &&
        (name.contains("Bundle", ignoreCase = true) ||
            name.contains("Package", ignoreCase = true) ||
            name.contains("Assemble", ignoreCase = true))
    ) {
        doFirst("verifyNoForegroundServiceEntries") {
            stripForegroundServiceEntriesFromGeneratedManifests()
            verifyNoForegroundServiceEntriesInGeneratedManifests()
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.14.1"))

    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-database")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-storage")
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-config")
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    // The line above only reports uncaught JVM exceptions. Our Swift runs as
    // native code (libTeacherMinute.so), so a crash in the app's own UI or
    // model layer arrives as a SIGSEGV and never reaches the JVM reporter —
    // it has to be caught by the NDK signal handler instead. Without this
    // dependency every Swift crash on Android is invisible in Crashlytics.
    implementation("com.google.firebase:firebase-crashlytics-ndk")

    implementation("com.google.android.gms:play-services-auth:21.1.1")
    implementation("io.livekit:livekit-android:2.25.3")

    // Google Pay via Braintree — see AndroidGooglePayManager. Pulls in
    // braintree-core and play-services-wallet transitively.
    implementation("com.braintreepayments.api:google-pay:5.13.0")

    // PayPal via Braintree — see AndroidPayPalManager. Used to confirm a
    // teacher's PayPal payout account. Unlike Google Pay this is a browser
    // switch, so it also needs the App Link intent-filter in AndroidManifest
    // and the assetlinks.json served from Firebase Hosting.
    implementation("com.braintreepayments.api:paypal:5.13.0")
}
