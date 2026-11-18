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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Date

/**
 * The student's blocked teachers on Android, against the local Firebase
 * emulators. QA test plan:
 *
 *   AND-R-04  Settings → Privacy Controls lists a blocked teacher, and
 *             unblocking removes the block from the backend (IT-42: the list
 *             kept loading)
 *
 *     ./gradlew :app:connectedStudentDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=teacher.minute.StudentBlockedTeachersTest
 */
@RunWith(AndroidJUnit4::class)
class StudentBlockedTeachersTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)
    private lateinit var student: EmulatorBackend.Account
    private lateinit var teacher: EmulatorBackend.Account

    @Before
    fun setUp() {
        assumeTrue("the student app's test", context.packageName == "com.yaronj.student")
        assumeTrue("Firebase emulators not running", backend.isRunning())
        assumeTrue("needs a debug build on the emulators", AndroidFirebaseEmulator.host != null)

        student = backend.createAccount("blocking.student")
        backend.merge("users/${student.uid}", mapOf("role" to "student", "fullName" to "Blocking Student"))
        teacher = backend.createAccount("blocked.teacher")
        backend.merge("users/${teacher.uid}", mapOf("role" to "teacher", "fullName" to "Blocked Teacher"))
        // What blockTeacher writes.
        backend.merge(
            "users/${student.uid}/blockedTeachers/${teacher.uid}",
            mapOf("teacherName" to "Blocked Teacher", "questionId" to "q-test", "blockedAt" to Date())
        )

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

    /** AND-R-04: the blocked teacher is listed, and Unblock clears the block. */
    @Test
    fun theBlockedTeacherIsListedAndCanBeUnblocked() {
        val blockPath = "users/${student.uid}/blockedTeachers/${teacher.uid}"
        assertNotNull("the block was not seeded", backend.strings(blockPath))

        logIn()
        openSideMenu(30_000)
        tap("side_menu_item_settings", "the menu's Settings row")
        scrollTo(By.res("settings_row_privacyControls"))?.click()
            ?: failWithScreen("settings", "Settings has no Privacy Controls row")

        val unblock = scrollTo(By.res("unblock_teacher_${teacher.uid}"), attempts = 10)
            ?: failWithScreen("blocked-list", "the blocked teacher was never listed")
        unblock.click()

        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && backend.strings(blockPath) != null) {
            Thread.sleep(500)
        }
        assertNull("unblocking left the block in the backend", backend.strings(blockPath))
        if (!device.wait(Until.gone(By.res("unblock_teacher_${teacher.uid}")), 15_000)) {
            failWithScreen("unblocked", "the unblocked teacher is still listed")
        }
    }

    // Steps, as in StudentAccountTest

    private fun logIn() {
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
        if (!device.wait(Until.gone(By.res("email_input")), 90_000) ||
            device.wait(Until.findObject(By.res("side_menu_button")), 30_000) == null
        ) {
            failWithScreen("login", "logging in did not reach the home screen")
        }
    }

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

    private fun type(text: String, into: String) {
        val tagged = device.findObject(By.res(into)) ?: failWithScreen(into, "no $into")
        val field = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    private fun scrollTo(selector: BySelector, attempts: Int = 6): UiObject2? {
        var found = device.wait(Until.findObject(selector), 10_000)
        repeat(attempts) {
            if (found != null) return@repeat
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f)
            found = device.wait(Until.findObject(selector), 3_000)
        }
        return found
    }

    private fun failWithScreen(name: String, message: String): Nothing {
        val dir = java.io.File(context.filesDir, "ui-test").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "student-$name.png"))
        java.io.File(dir, "student-$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        val text = device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }.filter { it.isNotBlank() }
        fail("$message: ${text.joinToString(" | ")}")
        throw AssertionError(message)
    }
}
