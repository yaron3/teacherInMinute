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
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A signed-in student asking a question, all the way to Send, against the
 * local Firebase emulators — the twin of the iOS StudentAskUITests. QA test
 * plan:
 *
 *   AND-D-01  text of 10+ characters → Find a teacher: the search screen, a
 *             searching question with that text, invite cards; closing the
 *             search cancels it
 *   AND-D-03  under 10 characters is refused on the phone, nothing sent; over
 *             the 1024-character limit the backend refuses with the limit
 *   AND-D-04  under 2 minutes → the "not enough minutes" offer, nothing sent
 *   AND-D-05  over the allowance of lessons a minute → "asking too quickly",
 *             nothing sent
 *
 * Sending is safe only because a debug build on the emulators talks to nothing
 * else, and the only teachers online are emulator records. The rate limit
 * counts lessons a teacher accepted, not questions asked, so AND-D-05 seeds
 * two recent lessons rather than asking three times.
 *
 *     ./gradlew :app:connectedStudentDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=teacher.minute.StudentAskTest
 */
@RunWith(AndroidJUnit4::class)
class StudentAskTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)
    private var teacherUid: String? = null

    private val searchCancel: BySelector = By.res("search_details_cancel")

    // Each in English, then Hebrew (backend/Firebase/remote_config_tim.json).
    private val tooShortMessages = listOf("Take a photo of it, or write at least 10 characters.", "צלם אותה, או כתוב לפחות 10 תווים.")
    private val tooLongMessages = listOf("Please shorten it to 1024 characters.", "קצרו אותה ל-1024 תווים.")
    private val tooQuicklyMessages = listOf("You're asking too quickly.", "שליחת השאלות מהירה מדי.")

    @Before
    fun setUp() {
        assumeTrue("the student app's test", context.packageName == "com.yaronj.student")
        assumeTrue("Firebase emulators not running", backend.isRunning())
        assumeTrue("needs a debug build on the emulators", AndroidFirebaseEmulator.host != null)

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

    @After
    fun tearDown() {
        // Nobody stays online on the emulators after the suite.
        teacherUid?.let { uid ->
            runCatching { backend.patch("teachers/$uid", JSONObject().put("status", "offline")) }
        }
    }

    /** AND-D-01: a text question goes out, and closing the search cancels it. */
    @Test
    fun askingWithTextStartsASearch() {
        val student = signedInStudent(minutes = 60)
        bringATeacherOnline()
        val text = "What is the derivative of x squared? ${(1000..9999).random()}"

        ask(text)
        if (!device.wait(Until.hasObject(searchCancel), 30_000)) failWithScreen("search", "Find a teacher did not start a search")

        val qid = waitForQuestion(student.uid)
        val question = backend.fields("questions/$qid") ?: JSONObject()
        assertEquals(text, stringValue(question, "text"))
        assertTrue(
            "the question is ${stringValue(question, "status")}",
            stringValue(question, "status") in listOf("searching", "accepted")
        )
        val invited = invitedTeachers(qid)
        assertTrue("the question was sent to no teacher", invited.isNotEmpty())
        assertTrue("an invited teacher has no card", backend.exists("teacherInvites/${invited.first()}/$qid"))

        device.findObject(searchCancel).click()
        var status = ""
        repeat(20) {
            if (status != "cancelled") {
                status = stringValue(backend.fields("questions/$qid") ?: JSONObject(), "status") ?: ""
                if (status != "cancelled") Thread.sleep(500)
            }
        }
        assertEquals("closing the search did not cancel the question", "cancelled", status)
        if (!waitForHome(20_000)) failWithScreen("home", "closing the search did not return home")
    }

    /** AND-D-03: fewer than 10 characters never leaves the phone. */
    @Test
    fun aShortQuestionIsRefusedOnThePhone() {
        val student = signedInStudent(minutes = 60)
        bringATeacherOnline()

        ask("2+2=?")

        waitForText(tooShortMessages, 15_000) ?: failWithScreen("short", "a short question showed no message")
        assertFalse("a short question started a search", device.hasObject(searchCancel))
        assertEquals("a short question was sent", 0, backend.count("questions", "studentUid", student.uid))
    }

    /** AND-D-03: over the length limit, the backend refuses with the limit. */
    @Test
    fun aTooLongQuestionIsRefusedWithTheLimit() {
        val student = signedInStudent(minutes = 60)
        bringATeacherOnline()

        ask("Long question. ".repeat(70)) // 1050 characters

        waitForText(tooLongMessages, 30_000) ?: failWithScreen("long", "a long question showed no length message")
        assertEquals("a question over the limit was sent", 0, backend.count("questions", "studentUid", student.uid))
    }

    /** AND-D-04: one minute left is not enough to ask. */
    @Test
    fun tooFewMinutesOffersMinutesInstead() {
        val student = signedInStudent(minutes = 1)
        bringATeacherOnline()

        ask("How do I factor x squared minus nine?")

        if (!device.wait(Until.hasObject(By.res("not_enough_minutes_primary")), 20_000)) {
            failWithScreen("minutes", "one minute left did not offer minutes")
        }
        assertFalse("a student without minutes started a search", device.hasObject(searchCancel))
        assertEquals("a student without minutes sent a question", 0, backend.count("questions", "studentUid", student.uid))
    }

    /** AND-D-05: two lessons in the last minute use up the allowance. */
    @Test
    fun askingTooQuicklyIsRefusedWithAWait() {
        val student = signedInStudent(minutes = 60)
        bringATeacherOnline()
        val now = System.currentTimeMillis()
        backend.merge("rateLimits/${student.uid}", mapOf("sessionsAt" to listOf(now - 20_000, now - 10_000)))

        ask("How do I factor x squared minus nine?")

        waitForText(tooQuicklyMessages, 30_000) ?: failWithScreen("rate", "asking too quickly showed no wait")
        assertEquals("a rate-limited question was sent", 0, backend.count("questions", "studentUid", student.uid))
    }

    // Steps

    /** A student account with `minutes`, signed in through the guest's menu. */
    private fun signedInStudent(minutes: Int): EmulatorBackend.Account {
        val student = backend.createAccount("ask.student")
        backend.merge(
            "users/${student.uid}",
            mapOf("role" to "student", "fullName" to "Asking Student", "remainingMinutes" to minutes, "totalMinutes" to minutes)
        )
        val start = device.wait(Until.findObject(By.res("student_intro_start")), 60_000)
            ?: failWithScreen("intro", "the intro's Start never appeared")
        start.click()
        // Right after a relaunch the old intro can swallow the first tap.
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && !device.wait(Until.gone(By.res("student_intro_start")), 3_000)) {
            runCatching { device.findObject(By.res("student_intro_start"))?.click() }
        }
        if (!waitForHome(60_000)) failWithScreen("home", "Start did not reach home")

        device.findObject(By.res("side_menu_button"))?.click() ?: failWithScreen("menu", "no menu button")
        val logIn = device.wait(Until.findObject(By.res("side_menu_log_in")), 15_000)
            ?: failWithScreen("menu", "no Log in in a guest's menu")
        logIn.click()
        if (!device.wait(Until.hasObject(By.res("email_input")), 20_000)) failWithScreen("login", "the login form did not open")
        type(student.email, into = "email_input")
        type(student.password, into = "password_input")
        device.findObject(By.res("login_submit")).click()
        if (!device.wait(Until.gone(By.res("email_input")), 90_000) || !waitForHome(90_000)) {
            failWithScreen("login", "logging in did not reach home")
        }
        return student
    }

    /** One teacher online on the emulators, so the app has someone to ask. */
    private fun bringATeacherOnline() {
        val uid = "ask-teacher-${System.currentTimeMillis()}"
        teacherUid = uid
        backend.merge("users/$uid", mapOf("role" to "teacher", "fullName" to "Emulator Teacher"))
        backend.put(
            "teachers/$uid",
            JSONObject().put("status", "offline").put("subjects", JSONArray().put("algebra").put("calculus"))
                .put("displayName", "Emulator Teacher")
        )
        backend.patch("teachers/$uid", JSONObject().put("status", "online").put("lastSeenAt", System.currentTimeMillis()))
        var listed = false
        repeat(30) {
            if (!listed) {
                listed = backend.exists("onlineTeachers/$uid")
                if (!listed) Thread.sleep(500)
            }
        }
        assertTrue("the emulator teacher was never listed online", listed)
    }

    /** Opens the text tab, writes `text` and taps Find a teacher. */
    private fun ask(text: String) {
        val tab = device.wait(Until.findObject(By.res("question_home_mode_text")), 20_000)
            ?: failWithScreen("text-tab", "no Text tab at home")
        tab.click()
        type(text, into = "question_text")
        device.pressBack() // the keyboard
        val find = device.wait(Until.findObject(By.res("find_teacher")), 15_000)
            ?: failWithScreen("find", "no Find a teacher")
        find.click()
    }

    private fun waitForQuestion(studentUid: String): String {
        repeat(40) {
            backend.documentIds("questions", "studentUid", studentUid).firstOrNull()?.let { return it }
            Thread.sleep(500)
        }
        failWithScreen("question", "no question was created")
    }

    private fun invitedTeachers(qid: String): List<String> {
        repeat(20) {
            val values = backend.fields("questions/$qid")?.optJSONObject("alreadyInvited")
                ?.optJSONObject("arrayValue")?.optJSONArray("values") ?: JSONArray()
            val invited = (0 until values.length()).map { values.getJSONObject(it).optString("stringValue") }
            if (invited.isNotEmpty()) return invited
            Thread.sleep(500)
        }
        return emptyList()
    }

    /** Home, past whatever a student may be shown first. */
    private fun waitForHome(timeoutMs: Long): Boolean {
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

    private fun waitForText(texts: List<String>, timeoutMs: Long): String? {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val screen = screenText()
            texts.firstOrNull { screen.contains(it) }?.let { return it }
            Thread.sleep(500)
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

    private fun screenText(): String =
        device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }
            .filter { it.isNotBlank() }.joinToString(" | ")

    private fun stringValue(fields: JSONObject, key: String): String? =
        fields.optJSONObject(key)?.optString("stringValue")?.takeIf { it.isNotEmpty() }

    /** Saves a screenshot and the hierarchy to files/ui-test, then fails. */
    private fun failWithScreen(name: String, message: String): Nothing {
        val dir = java.io.File(context.filesDir, "ui-test").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "ask-$name.png"))
        java.io.File(dir, "ask-$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
