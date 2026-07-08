package teacher.minute

import android.os.Handler
import android.os.Looper
import com.google.firebase.crashlytics.FirebaseCrashlytics

object AndroidCrashlyticsManager {
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
