package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-49: the dashboard shows when this phone has lost its connection to the
 * database the questions arrive on, instead of a Status chip that always read
 * "Connected". On Android nothing watched the connection at all.
 *
 *  1. Signed in and online, the Status chip reads "Connected".
 *  2. The app's database connection is cut, as losing the network does.
 *  3. The chip reads "No connection" and the warning banner is up.
 *
 * The way back is not covered here: on the emulator a dropped connection never
 * comes back in the same process (real phones do reconnect). For the same
 * reason, run this class on its own, or the tests after it find their app
 * with no connection. Runs on the local Firebase emulators; see
 * ProTeacherAcceptRaceTest for how.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherConnectionStatusTest : ProTeacherEmulatorTest() {

    private val banner = "No connection to the server"

    /**
     * Polls with a scroll between reads. The Status card sits below the fold,
     * and UiAutomator's view of a Compose screen that never goes idle (the
     * invite poll runs every 250 ms) can lag the screen itself: a banner on
     * the screenshot was missing from it. A scroll brings the card into view
     * and refreshes that view.
     */
    private fun waitFor(timeoutMs: Long, condition: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return true
            device.swipe(device.displayWidth / 2, device.displayHeight * 2 / 3, device.displayWidth / 2, device.displayHeight / 3, 20)
            Thread.sleep(1_000)
        }
        return condition()
    }

    @Test
    fun theStatusChipShowsALostConnection() {
        assertTrue(
            "the Status chip never read Connected: ${screenText()}",
            device.wait(Until.hasObject(By.text("Connected")), 30_000)
        )
        assertTrue("the warning was up while connected", !device.hasObject(By.textContains(banner)))

        com.google.firebase.database.FirebaseDatabase.getInstance().goOffline()

        assertTrue(
            "no warning banner with the connection lost: ${screenText()}",
            waitFor(15_000) { device.hasObject(By.textContains(banner)) }
        )
        assertTrue(
            "the Status chip did not say the connection was lost: ${screenText()}",
            waitFor(15_000) { device.hasObject(By.text("No connection")) }
        )
        assertTrue("the chip still read Connected", !device.hasObject(By.text("Connected")))
    }
}
