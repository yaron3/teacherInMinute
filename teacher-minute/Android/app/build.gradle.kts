import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension
import org.gradle.api.GradleException
import java.util.Properties

plugins {
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.android.application)
    id("skip-build-plugin")
    id("com.google.gms.google-services") version "4.4.4"
    id("com.google.firebase.crashlytics") version "3.0.6"
}

// The Kotlin Android plugin, applied here rather than in plugins { } above.
//
// It has to be applied: app/src/main/kotlin holds 22 hand-written Kotlin files,
// among them Main.kt, which declares the teacher.minute.AndroidAppMain that the
// manifest names as the Application class. Without the plugin this module has
// no Kotlin compilation at all — no :app:compileDebugKotlin task — so none of
// them reach the APK, and the app dies at launch on a ClassNotFoundException
// for AndroidAppMain. Gradle does not warn about a source set with no compiler
// attached, so that failure looks like a successful build. (`skip gradle` does
// ask for the plugin to go, and it is right for an app module that is all
// transpiled Swift, as Skip's own samples are. This one is not.)
//
// It cannot go in plugins { }: libs.plugins.kotlin.android no longer exists in
// the generated catalog, and a bare id there is resolved as a plugin marker
// from a repository, which Gradle refuses without a version. apply() instead
// looks the id up on the buildscript classpath, where the Kotlin Gradle plugin
// already is — the same classpath that makes the KotlinCompile and JvmTarget
// references further down this file resolve.
apply(plugin = "org.jetbrains.kotlin.android")

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
// plugin. This script applies no Kotlin plugin: `skip gradle` asked for the
// kotlin.android alias to be removed and the generated catalog no longer
// defines it, so neither accessor exists here and naming either one fails
// script compilation. The task type comes from the Kotlin Gradle plugin on the
// buildscript classpath, which needs no accessor.
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
            // frames. The upload is a separate task, so a release build stays
            // offline unless you ask for it:
            //   ./gradlew :app:assembleRelease :app:uploadCrashlyticsSymbolFileRelease
            configure<CrashlyticsExtension> {
                nativeSymbolUploadEnabled = true
                // The .so files as Swift produced them, before AGP strips them.
                unstrippedNativeLibsDir = layout.buildDirectory.dir(
                    "intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib"
                )
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
