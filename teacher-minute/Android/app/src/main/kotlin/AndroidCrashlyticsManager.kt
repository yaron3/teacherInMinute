package teacher.minute

import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.crashlytics.FirebaseCrashlytics

object AndroidCrashlyticsManager {
    /**
     * Tags every report with the device and the signed-in user from the first
     * line of `AndroidAppMain.onCreate`, before the Swift libraries load.
     * Swift's `AnalyticsService.setUser` sets the user too, but only once
     * Swift is up and auth has resolved, which is too late for a crash during
     * launch (such as a Swift library that fails to load). Firebase Auth keeps
     * the signed-in user on disk, so the user ID is known before anything else
     * has run.
     *
     * - `device_type`: manufacturer and model, the same string the admin
     *   dashboard shows (`deviceStatus.deviceType`).
     * - `device_abis`: the ABIs the device supports, in preference order.
     *   That order decides which native libraries Play installs, and Play's
     *   test devices report a phone model they are not.
     */
    @JvmStatic
    fun setLaunchKeys() {
        val crashlytics = FirebaseCrashlytics.getInstance()
        crashlytics.setCustomKey("device_type", AndroidDeviceInfoManager.deviceModel())
        crashlytics.setCustomKey("device_abis", Build.SUPPORTED_ABIS.joinToString(","))
        FirebaseAuth.getInstance().currentUser?.uid?.let { crashlytics.setUserId(it) }
    }

    @JvmStatic
    fun triggerTestCrash() {
        if (!BuildConfig.DEBUG) {
            return
        }

        FirebaseCrashlytics.getInstance().log("debug_crashlytics_test_crash")
        Handler(Looper.getMainLooper()).post {
            throw RuntimeException("Debug Crashlytics test crash")
        }
    }
}
