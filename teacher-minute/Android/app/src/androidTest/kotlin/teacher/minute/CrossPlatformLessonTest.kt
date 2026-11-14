package teacher.minute

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Android halves of the cross-platform sanity run: a lesson between an
 * iPhone and an Android phone, against the local Firebase emulators.
 * scripts/ui-tests/run_cross_platform_sanity.sh pairs each with the iOS half
 * that speaks the same protocol as the iOS twin it stands in for:
 *
 *   teachesALessonAndEndsIt    Pro Teacher on Android, with the iOS student's
 *                              StudentAskUITests
 *                              .testTakingALessonTheTeacherEndsThenSkippingTheRating
 *   asksAndTakesALesson        Instant Teacher on Android, with the iOS
 *                              teacher's ProTeacherLessonUITests
 *                              .testTeachingALessonAndEndingIt
 *
 * The protocol, through the emulators only: the teacher signs in and comes
 * online; the student, seeing it listed, takes every other teacher offline,
 * asks and picks a text lesson; the teacher accepts once the question says
 * text; both enter the lesson; after 35 seconds the teacher ends it and the
 * student closes the rating.
 *
 * Skipped unless the run passes the teacher's account: lessonTeacherEmail,
 * lessonTeacherPassword and lessonTeacherUid (the student half needs only the
 * uid), and questionText optionally.
 */
@RunWith(AndroidJUnit4::class)
class CrossPlatformLessonTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)
    private val args = InstrumentationRegistry.getArguments()

    private val endButton: BySelector = By.res("session_end_button")
    private val textOnly: BySelector = By.res("connection_setup_continue_as_text")

    @Before
    fun setUp() {
        assumeTrue("pass lessonTeacherUid: run through scripts/ui-tests/run_cross_platform_sanity.sh",
            args.getString("lessonTeacherUid") != null)
        assumeTrue("Firebase emulators not running", backend.isRunning())
        assumeTrue("needs a debug build on the emulators", AndroidFirebaseEmulator.host != null)

        FirebaseAuth.getInstance().signOut()
        val permissions = mutableListOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) permissions += android.Manifest.permission.POST_NOTIFICATIONS
        for (permission in permissions) {
            runCatching { instrumentation.uiAutomation.grantRuntimePermission(context.packageName, permission) }
        }
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
    }

    // Teacher

    @Test
    fun teachesALessonAndEndsIt() {
        assumeTrue("the teacher app's half", context.packageName == "com.yaronj.tim")
        val email = args.getString("lessonTeacherEmail")
        val password = args.getString("lessonTeacherPassword")
        assumeTrue("pass lessonTeacherEmail and lessonTeacherPassword", email != null && password != null)
        val uid = args.getString("lessonTeacherUid")!!

        openTeacherLogin()
        type(email!!, into = "email_input")
        type(password!!, into = "password_input")
        device.findObject(By.res("login_submit")).click()
        if (!device.wait(Until.hasObject(By.res("availability_toggle")), 90_000)) {
            failWithScreen("teacher-dashboard", "signing in did not reach the dashboard")
        }
        var online = false
        for (attempt in 0 until 40) {
            online = backend.exists("onlineTeachers/$uid")
            if (online) break
            // Switched on by hand if it did not come online by itself.
            if (attempt == 10) device.findObject(By.res("availability_toggle"))?.let { holdTap(it) }
            Thread.sleep(1_000)
        }
        if (!online) failWithScreen("teacher-online", "the teacher never came online")

        // The student's half asks once this teacher is listed; the card names
        // the question.
        val qid = waitFor(300_000) { backend.childKeys("teacherInvites/$uid").firstOrNull() }
            ?: failWithScreen("teacher-invite", "no question reached the teacher")
        val type = waitFor(120_000) { backend.strings("questions/$qid")?.get("conversationType")?.takeIf { it == "text" } }
            ?: failWithScreen("teacher-type", "the student never chose a text lesson")
        val accept = device.wait(Until.findObject(By.res("invite_accept_$qid")), 60_000)
            ?: failWithScreen("teacher-card", "the question's card never showed")
        accept.click()

        enterTheLesson("teacher")
        assertEquals("the live question does not name this teacher", uid,
            backend.strings("questions/$qid")?.get("acceptedByTeacher"))
        assertEquals("text", type)

        Thread.sleep(35_000)
        device.findObject(endButton)?.click() ?: failWithScreen("teacher-end", "End was never there")
        val confirm = device.wait(Until.findObject(By.res("chat_end_prompt_primary")), 15_000)
            ?: failWithScreen("teacher-end-confirm", "ending asked nothing")
        confirm.click()
        if (!device.wait(Until.gone(endButton), 60_000)) failWithScreen("teacher-left", "ending did not leave the lesson")
        expectTheLessonOver(qid, uid)

        // Nobody stays online on the emulators after the run.
        backend.patch("teachers/$uid", JSONObject().put("status", "offline"))
    }

    // Student

    @Test
    fun asksAndTakesALesson() {
        assumeTrue("the student app's half", context.packageName == "com.yaronj.student")
        val teacher = args.getString("lessonTeacherUid")!!
        val text = args.getString("questionText") ?: "Help me with quadratic equations, please"
        val student = signedInStudent()

        // The teacher's half signs in meanwhile. Once it is online it is made
        // the only teacher online, so the question reaches it.
        waitFor(240_000) { if (backend.exists("onlineTeachers/$teacher")) true else null }
            ?: failWithScreen("student-wait", "the teacher's half never came online")
        for (uid in backend.childKeys("teachers")) {
            if (uid != teacher) backend.patch("teachers/$uid", JSONObject().put("status", "offline"))
        }

        val tab = device.wait(Until.findObject(By.res("question_home_mode_text")), 20_000)
            ?: failWithScreen("student-tab", "no Text tab at home")
        tab.click()
        type(text, into = "question_text")
        device.pressBack() // the keyboard
        (device.wait(Until.findObject(By.res("find_teacher")), 15_000)
            ?: failWithScreen("student-find", "no Find a teacher")).click()
        if (!device.wait(Until.hasObject(By.res("search_details_cancel")), 30_000)) {
            failWithScreen("student-search", "Find a teacher did not start a search")
        }
        val qid = waitFor(20_000) { backend.documentIds("questions", "studentUid", student.uid).firstOrNull() }
            ?: failWithScreen("student-question", "no question was created")

        // A text lesson, chosen on the search screen's last step; the teacher's
        // half waits for it before accepting.
        var choice = device.findObject(By.res("search_choice_text"))
        repeat(4) {
            if (choice == null) {
                device.findObject(By.res("search_details_next"))?.click()
                choice = device.wait(Until.findObject(By.res("search_choice_text")), 3_000)
            }
        }
        (choice ?: failWithScreen("student-choice", "the search screen offers no text lesson")).click()
        waitFor(15_000) { stringValue(backend.fields("questions/$qid"), "conversationType")?.takeIf { it == "text" } }
            ?: failWithScreen("student-type", "choosing text did not reach the question")

        enterTheLesson("student")
        // The teacher's half ends it after 35 seconds; the rating shows it.
        val close = device.wait(Until.findObject(By.res("rate_session_close")), 180_000)
            ?: failWithScreen("student-rating", "the teacher's ending never reached the student")
        close.click()
        if (!device.wait(Until.hasObject(By.res("question_home_mode_text")), 30_000)) {
            failWithScreen("student-home", "closing the rating did not return home")
        }
        expectTheLessonOver(qid, teacher)
    }

    // Steps

    private fun openTeacherLogin() {
        repeat(5) {
            if (device.hasObject(By.res("email_input"))) return
            // On a short phone the welcome screen's Log in sits below the fold.
            val logIn = device.wait(Until.findObject(By.res("welcome_log_in")), 15_000) ?: run {
                device.swipe(device.displayWidth / 2, device.displayHeight * 3 / 4, device.displayWidth / 2, device.displayHeight / 4, 20)
                device.wait(Until.findObject(By.res("welcome_log_in")), 10_000)
            }
            logIn?.click()
            device.wait(Until.hasObject(By.res("email_input")), 5_000)
        }
        if (!device.hasObject(By.res("email_input"))) failWithScreen("teacher-login", "the login form never opened")
    }

    /** A student account with an hour of minutes, signed in through the guest's menu. */
    private fun signedInStudent(): EmulatorBackend.Account {
        val student = backend.createAccount("sanity.student")
        backend.merge(
            "users/${student.uid}",
            mapOf("role" to "student", "fullName" to "Sanity Student", "remainingMinutes" to 60, "totalMinutes" to 60)
        )
        val start = device.wait(Until.findObject(By.res("student_intro_start")), 60_000)
            ?: failWithScreen("student-intro", "the intro's Start never appeared")
        start.click()
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && !device.wait(Until.gone(By.res("student_intro_start")), 3_000)) {
            runCatching { device.findObject(By.res("student_intro_start"))?.click() }
        }
        if (!waitForStudentHome(60_000)) failWithScreen("student-home", "Start did not reach home")
        (device.findObject(By.res("side_menu_button")) ?: failWithScreen("student-menu", "no menu button")).click()
        (device.wait(Until.findObject(By.res("side_menu_log_in")), 15_000)
            ?: failWithScreen("student-menu", "no Log in in a guest's menu")).click()
        if (!device.wait(Until.hasObject(By.res("email_input")), 20_000)) failWithScreen("student-login", "the login form did not open")
        type(student.email, into = "email_input")
        type(student.password, into = "password_input")
        device.findObject(By.res("login_submit")).click()
        if (!device.wait(Until.gone(By.res("email_input")), 90_000) || !waitForStudentHome(90_000)) {
            failWithScreen("student-login", "logging in did not reach home")
        }
        return student
    }

    /** Into the lesson, by text only where the phone offers the choice. */
    private fun enterTheLesson(side: String) {
        val deadline = System.currentTimeMillis() + 300_000
        while (System.currentTimeMillis() < deadline && !device.hasObject(endButton)) {
            device.findObject(textOnly)?.let { runCatching { it.click() } }
            Thread.sleep(1_000)
        }
        if (!device.hasObject(endButton)) failWithScreen("$side-lesson", "the $side never entered the lesson")
    }

    /** The question completed and the teacher free. */
    private fun expectTheLessonOver(qid: String, teacher: String) {
        val over = waitFor(60_000) {
            val status = stringValue(backend.fields("questions/$qid"), "status")
            if (status == "completed" && backend.value("teachers/$teacher/busy") == null) true else null
        }
        if (over == null) {
            fail("the lesson did not end: status ${stringValue(backend.fields("questions/$qid"), "status")}, " +
                "busy ${backend.value("teachers/$teacher/busy")}")
        }
    }

    private fun waitForStudentHome(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res("student_tutorial_skip"))?.let { runCatching { it.click() } }
            device.findObject(By.res("permissions_setup_skip"))?.let { runCatching { it.click() } }
            device.findObject(By.res("verify_email_not_now"))?.let { runCatching { it.click() } }
            if (device.hasObject(By.res("question_home_mode_text")) && !device.hasObject(By.res("student_tutorial_skip")) &&
                !device.hasObject(By.res("email_input"))
            ) return true
            Thread.sleep(1_000)
        }
        return false
    }

    /** A switch takes a press held a moment, not a fast tap. */
    private fun holdTap(target: UiObject2) {
        val center = target.visibleCenter
        device.swipe(center.x, center.y, center.x, center.y, 10)
    }

    private fun <T> waitFor(timeoutMs: Long, probe: () -> T?): T? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            runCatching(probe).getOrNull()?.let { return it }
            Thread.sleep(1_000)
        }
        return null
    }

    /** SkipUI tags a container; the EditText inside it takes the text. */
    private fun type(text: String, into: String) {
        val tagged = device.wait(Until.findObject(By.res(into)), 20_000) ?: failWithScreen(into, "no $into")
        val field: UiObject2 = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    private fun stringValue(fields: JSONObject?, key: String): String? =
        fields?.optJSONObject(key)?.optString("stringValue")?.takeIf { it.isNotEmpty() }

    private fun screenText(): String =
        device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }
            .filter { it.isNotBlank() }.joinToString(" | ")

    /** Saves a screenshot and the hierarchy to files/ui-test, then fails. */
    private fun failWithScreen(name: String, message: String): Nothing {
        val dir = java.io.File(context.filesDir, "ui-test").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "cross-$name.png"))
        java.io.File(dir, "cross-$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
