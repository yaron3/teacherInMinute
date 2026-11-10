package teacher.minute

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.MemoryCacheSettings

/**
 * Debug builds only: points the app at the local Firebase emulators instead of
 * the live backend. The Android side of `FirebaseEmulator.swift`.
 *
 * Asked for through a JVM system property, which only an instrumented test can
 * set before the app starts: `EmulatorTestRunner` sets it in its `onCreate`,
 * which Android calls before `AndroidAppMain.onCreate`. A release build ignores
 * it.
 *
 * Firebase is then started for the emulators' demo project instead of the
 * production one in google-services.json. Firebase never resolves a demo
 * project to a real one, so nothing a function does while the app is on the
 * emulators can touch production. Analytics and Crashlytics are off.
 *
 * Unlike iOS, the emulator session shares the stored sign-in with production,
 * so run the tests on an emulator device rather than a phone signed in for
 * real.
 */
object AndroidFirebaseEmulator {
    private const val TAG = "AndroidFirebaseEmulator"

    const val PROJECT_ID = "demo-teacher-in-a-moment"
    const val HOST_PROPERTY = "teacher.minute.firebaseEmulatorHost"

    /** Ports pinned in backend/Firebase/firebase.json. */
    private const val AUTH_PORT = 9099
    private const val FIRESTORE_PORT = 8085
    private const val DATABASE_PORT = 9000
    private const val FUNCTIONS_PORT = 5001

    /** The Auth emulator accepts any key. */
    private const val API_KEY = "AIzaSyDemoEmulatorKeyForLocalTestsOnly0"

    /** The emulators' host as the device sees it, or null when not asked for. */
    val host: String?
        get() = if (BuildConfig.DEBUG) System.getProperty(HOST_PROPERTY)?.takeIf { it.isNotBlank() } else null

    /** Where callables are served, in place of the production cloudfunctions.net. */
    val functionsBaseUrl: String?
        get() = host?.let { "http://$it:$FUNCTIONS_PORT/$PROJECT_ID/us-central1" }

    /**
     * Starts Firebase: for the emulators when a test asked for them, as usual
     * otherwise. Must run before anything uses Firebase.
     *
     * Debug builds remove Firebase's own start-up provider
     * (src/debug/AndroidManifest.xml), so this is what starts it there. It
     * cannot be started for production and then replaced: Crashlytics' session
     * tracking opens a data file that a second app instance would open again,
     * and the process crashes. Release builds keep the provider, which has
     * started Firebase already by the time this runs.
     */
    @JvmStatic
    fun startFirebase(context: Context) {
        val host = host
        if (FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME }) {
            if (host != null) Log.e(TAG, "Firebase already started; the emulators cannot be used")
            return
        }
        if (host == null) {
            FirebaseApp.initializeApp(context)
            return
        }

        val base = FirebaseOptions.fromResource(context) ?: return
        val options = FirebaseOptions.Builder(base)
            .setApiKey(API_KEY)
            .setProjectId(PROJECT_ID)
            // The emulator's address itself, rather than useEmulator(): on
            // Android, useEmulator rewrites the first instance's address once it
            // connects, after which getInstance() no longer finds it under the
            // project's URL and hands later callers (the Kotlin managers) a new
            // instance aimed at the real servers. With the emulator as the URL,
            // every getInstance() resolves to the one instance. The namespace
            // is the bare project id, as the Functions emulator uses for a demo
            // project.
            .setDatabaseUrl("http://$host:$DATABASE_PORT?ns=$PROJECT_ID")
            .setStorageBucket("$PROJECT_ID.appspot.com")
            .build()
        FirebaseApp.initializeApp(context, options)

        FirebaseAnalytics.getInstance(context).setAnalyticsCollectionEnabled(false)
        FirebaseCrashlytics.getInstance().isCrashlyticsCollectionEnabled = false

        FirebaseAuth.getInstance().useEmulator(host, AUTH_PORT)
        FirebaseFirestore.getInstance().apply {
            useEmulator(host, FIRESTORE_PORT)
            firestoreSettings = FirebaseFirestoreSettings.Builder()
                .setLocalCacheSettings(MemoryCacheSettings.newBuilder().build())
                .build()
        }

        Log.i(TAG, "using the local emulators at $host, project $PROJECT_ID")
    }
}
