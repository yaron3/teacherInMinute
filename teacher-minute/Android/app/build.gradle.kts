import org.gradle.api.GradleException
import java.util.Properties

plugins {
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.android.application)
    id("skip-build-plugin")
    id("com.google.gms.google-services") version "4.4.4"
    id("com.google.firebase.crashlytics") version "3.0.6"
}

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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get().toString())
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
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
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
    implementation(platform("com.google.firebase:firebase-bom:33.0.0"))

    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-database")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")

    implementation("com.google.android.gms:play-services-auth:21.1.1")
    implementation("io.livekit:livekit-android:2.25.3")
}
