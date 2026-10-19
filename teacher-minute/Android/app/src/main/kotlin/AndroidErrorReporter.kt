package teacher.minute

import android.os.Bundle
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics

/**
 * The Kotlin side of `AnalyticsService.reportError`, for failures a manager
 * handles itself rather than handing back to Swift: logs to Logcat, sends the
 * same `app_error` Analytics event, and gives Crashlytics a log line and a
 * non-fatal. An error that reaches Swift is reported there instead.
 */
object AndroidErrorReporter {
    @JvmStatic
    fun report(tag: String, message: String, error: Throwable) {
        Log.e(tag, message, error)
        val source = "$tag.android"
        val detail = "$message: ${error.message ?: error.javaClass.simpleName}"
        try {
            val crashlytics = FirebaseCrashlytics.getInstance()
            crashlytics.log("error in $source: $detail")
            crashlytics.recordException(error)

            val params = Bundle().apply {
                putString("source", source.take(100))
                putString("message", detail.take(100))
                putString("error_domain", error.javaClass.name.take(100))
            }
            FirebaseAnalytics.getInstance(FirebaseApp.getInstance().applicationContext)
                .logEvent("app_error", params)
        } catch (reportError: Throwable) {
            // Firebase not up yet: Logcat above is all there is.
            Log.w(tag, "could not report error", reportError)
        }
    }
}
