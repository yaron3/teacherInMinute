package teacher.minute

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.google.firebase.auth.FirebaseAuth
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The student app's account deletion on Android, against the local Firebase
 * emulators. QA test plan:
 *
 *   AND-A-05  a student logs out from Settings and no session is left
 *   AND-A-08  an email/password student deletes their account and it is
 *             gone: no Auth user, no profile, no way back in
 *
 * It runs in the student flavor and skips itself in Pro Teacher:
 *
 *     ./gradlew :app:connectedStudentDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=teacher.minute.StudentAccountTest
 *
 * The emulators must be up, as for ProTeacherAcceptRaceTest.
 */
@RunWith(AndroidJUnit4::class)
class StudentAccountTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)
    private lateinit var student: EmulatorBackend.Account

    private val dialogButton: BySelector = By.res("dialog_confirm_button")

    @Before
    fun setUp() {
        assumeTrue("the student app's test", context.packageName == "com.yaronj.student")
        assumeTrue("Firebase emulators not running", backend.isRunning())
        assumeTrue("needs a debug build on the emulators", AndroidFirebaseEmulator.host != null)

        student = backend.createAccount("delete.student")
        backend.merge("users/${student.uid}", mapOf("role" to "student", "fullName" to "Delete Student"))
        // Only the server's deletion removes the profile's subcollections.
        backend.merge("users/${student.uid}/inbox/welcome", mapOf("title" to "Welcome"))

        // The test runs in the app's own process: start signed out, with the
        // prompts the home screen raises already answered.
        FirebaseAuth.getInstance().signOut()
        val permissions = mutableListOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) permissions += android.Manifest.permission.POST_NOTIFICATIONS
        for (permission in permissions) {
            instrumentation.uiAutomation.grantRuntimePermission(context.packageName, permission)
        }
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
    }

    /** AND-A-05: a student logs out from Settings and is signed out: the
     *  intro, or the menu offering Log in again, and no session left. */
    @Test
    fun loggingOutSignsTheStudentOut() {
        logIn()
        openAccountSecurity()
        tap("settings_row_logOut", "the Log Out row")
        val confirm = device.wait(Until.findObject(dialogButton), 10_000)
            ?: failWithScreen("logout-confirm", "the log-out confirmation did not appear")
        confirm.click()

        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && FirebaseAuth.getInstance().currentUser?.uid == student.uid) {
            Thread.sleep(500)
        }
        assertNotEquals("logging out left the student signed in", student.uid, FirebaseAuth.getInstance().currentUser?.uid)
        // Back where a student without an account starts.
        if (!device.wait(Until.hasObject(By.res("student_intro_start")), 30_000)) {
            openSideMenu(30_000)
            if (!device.wait(Until.hasObject(By.res("side_menu_log_in")), 10_000)) {
                failWithScreen("logout-end", "after logging out the app offers no way to log in again")
            }
        }
        assertTrue("the logged-out account was harmed", backend.canSignIn(student))
    }

    /** AND-A-08: an email/password student deletes their account. */
    @Test
    fun deletingTheAccountRemovesIt() {
        logIn()
        openAccountSecurity()
        scrollTo(By.res("settings_row_deleteAccount"))?.click()
            ?: failWithScreen("account-security", "Account & Security has no Delete Account row")

        // First "this cannot be undone", then the password.
        val confirm = device.wait(Until.findObject(dialogButton), 10_000)
            ?: failWithScreen("delete-confirm", "the delete confirmation did not appear")
        confirm.click()
        if (!device.wait(Until.hasObject(By.res("dialog_secure_input")), 20_000)) {
            failWithScreen("delete-password", "deleting did not ask for the password")
        }
        type(student.password, into = "dialog_secure_input")
        device.findObject(dialogButton).click()

        val deadline = System.currentTimeMillis() + 60_000
        while (System.currentTimeMillis() < deadline && !device.hasObject(By.res("student_intro_start"))) {
            if (device.hasObject(dialogButton) && !device.hasObject(By.res("dialog_secure_input"))) {
                failWithScreen("delete-failed", "deleting the account failed")
            }
            Thread.sleep(1_000)
        }
        if (!device.hasObject(By.res("student_intro_start"))) {
            failWithScreen("delete-end", "deleting the account did not return to the intro")
        }

        assertFalse("the deleted account can still sign in", backend.canSignIn(student))
        assertNull("the deleted student's profile is still there", backend.strings("users/${student.uid}"))
        assertNull("the deleted student's inbox is still there", backend.strings("users/${student.uid}/inbox/welcome"))
    }

    // Steps

    /** From the intro, through the menu's Log in, to the student's home. */
    private fun logIn() {
        // Only the home of a student without an account leads to the login form.
        // Tap until the intro is gone: right after a relaunch the previous
        // activity's intro can still be on screen and swallow the first tap.
        tap("student_intro_start", "the intro's start button", 60_000)
        val introDeadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < introDeadline && !device.wait(Until.gone(By.res("student_intro_start")), 3_000)) {
            runCatching { device.findObject(By.res("student_intro_start"))?.click() }
        }
        openSideMenu(60_000)
        tap("side_menu_log_in", "the menu's Log in link")
        assertNotNull("the login form did not open", device.wait(Until.findObject(By.res("email_input")), 20_000))
        type(student.email, into = "email_input")
        type(student.password, into = "password_input")
        device.findObject(By.res("login_submit")).click()
        // The home screen: the form is gone and the menu button is back.
        if (!device.wait(Until.gone(By.res("email_input")), 90_000) ||
            device.wait(Until.findObject(By.res("side_menu_button")), 30_000) == null
        ) {
            failWithScreen("login", "logging in did not reach the home screen")
        }
    }

    private fun openAccountSecurity() {
        openSideMenu(30_000)
        tap("side_menu_item_settings", "the menu's Settings row")
        scrollTo(By.res("settings_row_accountSecurity"))?.click()
            ?: failWithScreen("settings", "Settings has no Account & Security row")
        if (!device.wait(Until.hasObject(By.res("settings_row_logOut")), 15_000)) {
            failWithScreen("account-security", "Account & Security did not open")
        }
    }

    /** Opens the side menu, skipping the tutorial a new student is shown first. */
    private fun openSideMenu(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res("side_menu_button"))?.let { it.click(); return }
            device.findObject(By.res("student_tutorial_skip"))?.click()
            Thread.sleep(1_000)
        }
        failWithScreen("side-menu", "the side-menu button never appeared")
    }

    private fun tap(id: String, described: String, timeoutMs: Long = 15_000) {
        val element = device.wait(Until.findObject(By.res(id)), timeoutMs)
            ?: failWithScreen(id, "$described never appeared")
        element.click()
    }

    /** SkipUI tags a container; the EditText inside it takes the text. */
    private fun type(text: String, into: String) {
        val tagged = device.findObject(By.res(into)) ?: failWithScreen(into, "no $into")
        val field = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    private fun scrollTo(selector: BySelector): UiObject2? {
        var found = device.wait(Until.findObject(selector), 10_000)
        repeat(6) {
            if (found != null) return@repeat
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f)
            found = device.wait(Until.findObject(selector), 2_000)
        }
        return found
    }

    /** Saves a screenshot and the hierarchy to files/ui-test, then fails. */
    private fun failWithScreen(name: String, message: String): Nothing {
        val dir = java.io.File(context.filesDir, "ui-test").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "student-$name.png"))
        java.io.File(dir, "student-$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        val text = device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }.filter { it.isNotBlank() }
        fail("$message: ${text.joinToString(" | ")}")
        throw AssertionError(message)
    }
}
