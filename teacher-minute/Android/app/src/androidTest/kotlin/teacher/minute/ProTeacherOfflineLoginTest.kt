package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Until
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * AND-A-11: Pro Teacher logging in with the network off, against the local
 * Firebase emulators.
 *
 * Run it in its own instrumentation call, never in one with other suites:
 * turning Wi-Fi and data off and on leaves the app process's Firebase
 * connections slow to recover, and the tests that follow it in the same
 * process time out.
 *
 *     adb shell am instrument -w -e class teacher.minute.ProTeacherOfflineLoginTest \
 *       com.yaronj.tim.test/teacher.minute.EmulatorTestRunner
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherOfflineLoginTest : ProTeacherEmulatorTest() {

    override val signsInAtStart = false

    private val dialogButton: BySelector = By.res("dialog_confirm_button")

    /** AND-A-11: logging in with the network off says so, and the form stays
     *  usable; with the network back the same login works. */
    @Test
    fun loggingInOfflineShowsAnError() {
        setNetwork(enabled = false)
        try {
            submitLogin(appTeacher.email, appTeacher.password)
            val ok = device.wait(Until.findObject(dialogButton), 45_000)
            if (ok == null) {
                capture("offline-login")
                fail("no error after logging in offline: ${screenText()}")
            }
            println("[ProTeacherAccountTest] offline refusal: ${screenText()}")
            assertFalse("signed in with no network", device.hasObject(By.res("availability_toggle")))
            ok!!.click()
            assertTrue("the error stayed", device.wait(Until.gone(dialogButton), 10_000))
            assertTrue("the login form is gone", device.hasObject(By.res("email_input")))
        } finally {
            setNetwork(enabled = true)
        }
        signIn()
    }

    /**
     * Wi-Fi and mobile data on or off; the emulators are reached over them.
     *
     * Turning them back on waits for a working network, then reconnects the
     * Realtime Database and Firestore: their sockets were on the network that went away,
     * and their retry backoff would otherwise starve the tests that run after this
     * one in the same process.
     */
    private fun setNetwork(enabled: Boolean) {
        val verb = if (enabled) "enable" else "disable"
        for (radio in listOf("wifi", "data")) {
            instrumentation.uiAutomation.executeShellCommand("svc $radio $verb").close()
        }
        if (!enabled) {
            Thread.sleep(2_000)
            return
        }
        val connectivity = context.getSystemService(android.net.ConnectivityManager::class.java)
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline) {
            val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
            if (capabilities?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) break
            Thread.sleep(500)
        }
        com.google.firebase.database.FirebaseDatabase.getInstance().apply {
            goOffline()
            goOnline()
        }
        com.google.firebase.firestore.FirebaseFirestore.getInstance().apply {
            com.google.android.gms.tasks.Tasks.await(disableNetwork())
            com.google.android.gms.tasks.Tasks.await(enableNetwork())
        }
    }

}
