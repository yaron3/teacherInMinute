package teacher.minute

import android.os.Bundle
import androidx.test.runner.AndroidJUnitRunner

/**
 * Runs the instrumented tests against the local Firebase emulators.
 *
 * Android calls a runner's `onCreate` before the app's own
 * `Application.onCreate`, so the property set here is in place when
 * `AndroidFirebaseEmulator.configureIfRequested` reads it. The host defaults to
 * 10.0.2.2, the Mac as an Android emulator sees it; pass
 * `-Pandroid.testInstrumentationRunnerArguments.firebaseEmulatorHost=<host>`
 * for a device that reaches it elsewhere.
 */
class EmulatorTestRunner : AndroidJUnitRunner() {
    override fun onCreate(arguments: Bundle?) {
        val host = arguments?.getString("firebaseEmulatorHost") ?: DEFAULT_HOST
        System.setProperty(AndroidFirebaseEmulator.HOST_PROPERTY, host)
        super.onCreate(arguments)
    }

    companion object {
        const val DEFAULT_HOST = "10.0.2.2"
    }
}
