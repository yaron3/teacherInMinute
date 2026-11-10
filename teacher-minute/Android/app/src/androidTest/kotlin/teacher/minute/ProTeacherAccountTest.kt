package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.Until
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Pro Teacher's account life cycle on Android, against the real backend on the
 * local Firebase emulators — the twin of the iOS ProTeacherAccountUITests.
 * QA test plan:
 *
 *   AND-A-03  a wrong password, three times: an error each time, then the
 *             right one still works
 *   AND-A-06  logging out while online takes the teacher offline at once
 *   AND-A-09  deleting the account while online: offline, gone, never invited
 *
 * AND-A-07, the session surviving a relaunch, is not here: the test runs in
 * the app's own process, so it cannot kill the app and start it cold.
 *
 * Each test starts on the login form. Run like ProTeacherAcceptRaceTest.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherAccountTest : ProTeacherEmulatorTest() {

    override val signsInAtStart = false

    private val dialogButton: BySelector = By.res("dialog_confirm_button")

    /** AND-A-03: three wrong passwords, each refused; then the right one. */
    @Test
    fun wrongPasswordIsRefusedEachTime() {
        for (attempt in 1..3) {
            submitLogin(appTeacher.email, "Wrong-$attempt-${appTeacher.password}")
            val ok = device.wait(Until.findObject(dialogButton), 30_000)
            assertNotNull("attempt $attempt: no error", ok)
            println("[ProTeacherAccountTest] refusal $attempt: ${screenText()}")
            ok.click()
            assertTrue("attempt $attempt: the error stayed", device.wait(Until.gone(dialogButton), 10_000))
            assertTrue("attempt $attempt: the login form is gone", device.hasObject(By.res("email_input")))
            assertFalse("attempt $attempt: a wrong password signed in", device.hasObject(By.res("availability_toggle")))
        }
        signIn()
    }

    /** AND-A-06: logging out while online takes the teacher offline. */
    @Test
    fun loggingOutWhileOnlineGoesOffline() {
        signIn()
        assertTrue("the teacher never went online", waitForPresence(online = true))

        logOut()

        assertTrue(
            "still online after logging out: ${presence()}",
            waitForPresence(online = false, timeoutMs = 10_000)
        )
    }

    /** AND-A-09: deleting the account while online takes the teacher out of
     *  dispatch for good. */
    @Test
    fun deletingTheAccountWhileOnline() {
        signIn()
        prepareRealDispatch()
        assertTrue("the teacher never went online", waitForPresence(online = true))

        deleteAccount()

        assertFalse("the deleted account can still sign in", backend.canSignIn(appTeacher))
        assertNull("the deleted teacher's profile is still there", backend.strings("users/${appTeacher.uid}"))

        val asked = ask()
        assertTrue("dispatch did not run: the other teacher was not invited either", waitForInvite(otherTeacher, asked))
        Thread.sleep(5_000)
        assertFalse("the deleted teacher was invited", backend.exists("teacherInvites/${appTeacher.uid}/$asked"))

        assertTrue(
            "still online after deleting the account: ${presence()}",
            waitForPresence(online = false, timeoutMs = 15_000)
        )
    }

    // Steps

    private fun presence(): String =
        "status=${backend.value("teachers/${appTeacher.uid}/status")} " +
            "onlineTeachers=${backend.exists("onlineTeachers/${appTeacher.uid}")}"

    /** Waits until the app's teacher is online (status online and listed in
     *  onlineTeachers) or offline (neither). */
    private fun waitForPresence(online: Boolean, timeoutMs: Long = 30_000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val status = backend.value("teachers/${appTeacher.uid}/status")
            val projected = backend.exists("onlineTeachers/${appTeacher.uid}")
            if (if (online) status == "online" && projected else status != "online" && !projected) return true
            Thread.sleep(500)
        }
        return false
    }

    private fun logOut() {
        openAccountSecurity()
        device.findObject(By.res("settings_row_logOut")).click()
        val confirm = device.wait(Until.findObject(dialogButton), 10_000)
        assertNotNull("the log-out confirmation did not appear", confirm)
        confirm.click()
        assertTrue(
            "logging out did not return to the welcome screen",
            device.wait(Until.hasObject(By.res("welcome_log_in")), 30_000)
        )
    }

    private fun deleteAccount() {
        openAccountSecurity()
        val row = findScrolling(By.res("settings_row_deleteAccount"))
        assertNotNull("no Delete Account row", row)
        row!!.click()

        // First "this cannot be undone", then the password.
        val confirm = device.wait(Until.findObject(dialogButton), 10_000)
        assertNotNull("the delete confirmation did not appear", confirm)
        confirm.click()
        assertTrue(
            "deleting did not ask for the password",
            device.wait(Until.hasObject(By.res("dialog_secure_input")), 20_000)
        )
        type(appTeacher.password, into = "dialog_secure_input")
        device.findObject(dialogButton).click()

        val deadline = System.currentTimeMillis() + 60_000
        while (System.currentTimeMillis() < deadline && !device.hasObject(By.res("welcome_log_in"))) {
            if (device.hasObject(dialogButton) && !device.hasObject(By.res("dialog_secure_input"))) {
                capture("delete-account")
                fail("deleting the account failed: ${screenText()}")
            }
            Thread.sleep(1_000)
        }
        if (!device.hasObject(By.res("welcome_log_in"))) {
            capture("delete-account")
            fail("deleting the account did not return to the welcome screen: ${screenText()}")
        }
    }

    private fun openAccountSecurity() {
        val tab = device.wait(Until.findObject(By.res("tab_item_settings")), 15_000)
        assertNotNull("no Settings tab", tab)
        tab.click()
        val accountSecurity = findScrolling(By.res("settings_row_accountSecurity"))
        if (accountSecurity == null) {
            capture("settings")
            fail("Settings has no Account & Security row: ${screenText()}")
        }
        accountSecurity!!.click()
        if (!device.wait(Until.hasObject(By.res("settings_row_logOut")), 15_000)) {
            capture("account-security")
            fail("Account & Security did not open: ${screenText()}")
        }
    }

    /** Finds `selector`, scrolling the screen down for it a few times. */
    private fun findScrolling(selector: BySelector) = run {
        var found = device.wait(Until.findObject(selector), 10_000)
        repeat(6) {
            if (found != null) return@repeat
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f)
            found = device.wait(Until.findObject(selector), 2_000)
        }
        found
    }
}
