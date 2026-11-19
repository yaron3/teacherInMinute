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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
        // A cold start keeps the main thread busy for seconds after the window
        // shows (7 s on a loaded emulator). Input sent then is an ANR to
        // Android ("waited for FocusEvent"), so let the start finish first.
        device.waitForIdle(20_000)
        Thread.sleep(5_000)
        device.waitForIdle(20_000)
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
        shot("01-teacher-invite")
        accept.click()

        enterTheLesson("teacher")
        assertEquals("the live question does not name this teacher", uid,
            backend.strings("questions/$qid")?.get("acceptedByTeacher"))
        assertEquals("text", type)

        if (sessionShots) {
            // Session screenshots: a message, then the middle of the lesson,
            // inside the same 35 seconds.
            val started = System.currentTimeMillis()
            sendMessage("Hello! Let's move the 3 to the other side first.")
            Thread.sleep(15_000)
            shot("03-teacher-during")
            Thread.sleep(maxOf(0L, 35_000 - (System.currentTimeMillis() - started)))
        } else {
            Thread.sleep(35_000)
        }
        device.findObject(endButton)?.click() ?: failWithScreen("teacher-end", "End was never there")
        val confirm = device.wait(Until.findObject(By.res("chat_end_prompt_primary")), 15_000)
            ?: failWithScreen("teacher-end-confirm", "ending asked nothing")
        if (sessionShots) Thread.sleep(1_000)
        shot("04-teacher-end-confirm")
        confirm.click()
        if (!device.wait(Until.gone(endButton), 60_000)) failWithScreen("teacher-left", "ending did not leave the lesson")
        expectTheLessonOver(qid, uid)
        if (sessionShots) Thread.sleep(2_000)
        shot("05-teacher-after")

        // Nobody stays online on the emulators after the run.
        backend.patch("teachers/$uid", JSONObject().put("status", "offline"))
    }

    /** IT-42 end to end, the teacher's half — pairs with the iOS student's
     *  StudentAskUITests.testABlockedTeacherGetsNoQuestionsUntilUnblocked.
     *  The teacher takes the lesson; the student ends it, reports and blocks
     *  them, and asks again: that question must never show on this screen.
     *  Once the student unblocks and asks once more, its card shows here and
     *  is declined, which tells the student's half it was seen. */
    @Test
    fun teachesThenIsBlockedThenUnblocked() {
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
        comeOnline(uid)

        val qid = waitFor(300_000) { backend.childKeys("teacherInvites/$uid").firstOrNull() }
            ?: failWithScreen("teacher-invite", "no question reached the teacher")
        waitFor(120_000) { backend.strings("questions/$qid")?.get("conversationType")?.takeIf { it == "text" } }
            ?: failWithScreen("teacher-type", "the student never chose a text lesson")
        (device.wait(Until.findObject(By.res("invite_accept_$qid")), 60_000)
            ?: failWithScreen("teacher-card", "the question's card never showed")).click()
        enterTheLesson("teacher")
        val student = backend.strings("questions/$qid")?.get("studentUid")
            ?: failWithScreen("teacher-student", "the question names no student")

        // The student ends it; any note on the way out is closed.
        val ended = System.currentTimeMillis() + 300_000
        while (System.currentTimeMillis() < ended && device.hasObject(endButton)) {
            device.findObject(By.res("chat_end_prompt_primary"))?.let { runCatching { it.click() } }
            Thread.sleep(2_000)
        }
        if (device.hasObject(endButton)) failWithScreen("teacher-ended", "the student's ending never reached the teacher")
        expectTheLessonOver(qid, uid)
        device.wait(Until.findObject(By.res("dialog_confirm_button")), 5_000)?.let { runCatching { it.click() } }

        // Blocked: the student's next question must not show here.
        waitFor(300_000) { if (backend.strings("users/$student/blockedTeachers/$uid") != null) true else null }
            ?: failWithScreen("teacher-blocked", "the student never blocked the teacher")
        comeOnline(uid)
        val blockedQid = waitFor(300_000) {
            backend.documentIds("questions", "studentUid", student).firstOrNull { it != qid }
        } ?: failWithScreen("teacher-blocked-question", "the student never asked while the teacher was blocked")
        val watchUntil = System.currentTimeMillis() + 25_000
        while (System.currentTimeMillis() < watchUntil) {
            if (device.hasObject(By.res("invite_accept_$blockedQid"))) {
                failWithScreen("teacher-blocked-card", "the blocked teacher was shown the student's question")
            }
            assertFalse("the blocked teacher was sent the question", backend.exists("teacherInvites/$uid/$blockedQid"))
            Thread.sleep(1_000)
        }

        // Unblocked: the student's next question shows here, and is declined.
        waitFor(300_000) { if (backend.strings("users/$student/blockedTeachers/$uid") == null) true else null }
            ?: failWithScreen("teacher-unblocked", "the student never unblocked the teacher")
        val unblockedQid = waitFor(300_000) {
            backend.documentIds("questions", "studentUid", student).firstOrNull { it != qid && it != blockedQid }
        } ?: failWithScreen("teacher-unblocked-question", "the student never asked after unblocking")
        val decline = device.wait(Until.findObject(By.res("invite_decline_$unblockedQid")), 60_000)
            ?: failWithScreen("teacher-unblocked-card", "the unblocked teacher was never shown the student's question")
        decline.click()
        if (!device.wait(Until.gone(By.res("invite_accept_$unblockedQid")), 15_000)) {
            failWithScreen("teacher-declined", "the card stayed after declining")
        }

        backend.patch("teachers/$uid", JSONObject().put("status", "offline"))
    }

    /** Online and listed, switching availability on by hand if needed. */
    private fun comeOnline(uid: String) {
        var online = false
        for (attempt in 0 until 60) {
            online = backend.exists("onlineTeachers/$uid")
            if (online) break
            if (attempt == 10 || attempt == 40) device.findObject(By.res("availability_toggle"))?.let { holdTap(it) }
            Thread.sleep(1_000)
        }
        if (!online) failWithScreen("teacher-online", "the teacher never came online")
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
        shot("01-student-searching")

        enterTheLesson("student")
        if (sessionShots) {
            sendMessage("Hi! I'm stuck on 2x + 3 = 11.")
            Thread.sleep(12_000)
            shot("03-student-during")
        }
        // The teacher's half ends it after 35 seconds; the rating shows it.
        val close = device.wait(Until.findObject(By.res("rate_session_close")), 180_000)
            ?: failWithScreen("student-rating", "the teacher's ending never reached the student")
        if (sessionShots) Thread.sleep(1_000)
        shot("04-student-end-rating")
        close.click()
        if (!device.wait(Until.hasObject(By.res("question_home_mode_text")), 30_000)) {
            failWithScreen("student-home", "closing the rating did not return home")
        }
        if (sessionShots) Thread.sleep(1_000)
        shot("05-student-after")
        expectTheLessonOver(qid, teacher)
    }

    /** IT-42 end to end, the student's half — pairs with the iOS teacher's
     *  ProTeacherLessonUITests.testTeachingThenBeingBlockedThenUnblocked.
     *  After a lesson the student reports and blocks the teacher from the
     *  rating screen; a question asked then reaches no one; Privacy Controls
     *  lists the teacher and Unblock lifts the block; the next question
     *  reaches the teacher, whose half declines it from its card. */
    @Test
    fun asksBlocksThenUnblocksTheTeacher() {
        assumeTrue("the student app's half", context.packageName == "com.yaronj.student")
        val teacher = args.getString("lessonTeacherUid")!!
        val student = signedInStudent()

        waitFor(240_000) { if (backend.exists("onlineTeachers/$teacher")) true else null }
            ?: failWithScreen("student-wait", "the teacher's half never came online")
        for (uid in backend.childKeys("teachers")) {
            if (uid != teacher) backend.patch("teachers/$uid", JSONObject().put("status", "offline"))
        }

        // The lesson, which the student ends after 35 seconds (the rating is
        // offered only after 30).
        val qid = askAQuestion("Help me with quadratic equations, please", student.uid, emptyList())
        var choice = device.findObject(By.res("search_choice_text"))
        repeat(4) {
            if (choice == null) {
                device.findObject(By.res("search_details_next"))?.click()
                choice = device.wait(Until.findObject(By.res("search_choice_text")), 3_000)
            }
        }
        (choice ?: failWithScreen("student-choice", "the search screen offers no text lesson")).click()
        enterTheLesson("student")
        Thread.sleep(35_000)
        (device.findObject(endButton) ?: failWithScreen("student-end", "End was never there")).click()
        (device.wait(Until.findObject(By.res("chat_end_prompt_primary")), 15_000)
            ?: failWithScreen("student-end-confirm", "ending asked nothing")).click()
        device.wait(Until.findObject(By.text("Save to chat only")), 5_000)?.click()

        // Report, with "Also block" left as it starts: ticked.
        (device.wait(Until.findObject(By.res("rating_report_teacher")), 60_000)
            ?: failWithScreen("student-rating", "the rating screen offers no report")).click()
        (device.wait(Until.findObject(By.res("report_reason_not_teaching")), 15_000)
            ?: failWithScreen("student-report", "the report offers no reasons")).click()
        if (!device.wait(Until.hasObject(By.res("report_also_block")), 10_000)) {
            failWithScreen("student-report-block", "the report offers no block")
        }
        var send = device.findObject(By.res("report_send"))
        repeat(3) {
            if (send == null) {
                device.swipe(device.displayWidth / 2, device.displayHeight * 3 / 4, device.displayWidth / 2, device.displayHeight / 4, 20)
                send = device.wait(Until.findObject(By.res("report_send")), 3_000)
            }
        }
        (send ?: failWithScreen("student-report-send", "the report has no Send")).click()
        (device.wait(Until.findObject(By.res("report_done")), 30_000)
            ?: failWithScreen("student-report-done", "sending the report showed no confirmation")).click()
        waitFor(30_000) { if (backend.strings("users/${student.uid}/blockedTeachers/$teacher") != null) true else null }
            ?: failWithScreen("student-blocked", "the teacher is not on the student's blocked list")
        if (!waitForStudentHome(30_000)) failWithScreen("student-home", "not back home after the report")

        // Blocked: the teacher is the only one online, so this goes to nobody.
        val blockedQid = askAQuestion("Blocked check - this must not reach the teacher", student.uid, listOf(qid))
        val carried = backend.stringArray("questions/$blockedQid", "blockedTeachers")
        assertTrue("the question does not carry the block: $carried", teacher in carried)
        Thread.sleep(20_000)
        assertFalse("the blocked teacher was sent the question", backend.exists("teacherInvites/$teacher/$blockedQid"))
        device.findObject(By.res("search_details_cancel"))?.click()
        if (!waitForStudentHome(30_000)) failWithScreen("student-home", "closing the search did not return home")

        // Privacy Controls lists the teacher, and Unblock lifts the block.
        val settings = By.res("side_menu_item_settings")
        repeat(4) {
            if (!device.hasObject(settings)) {
                device.findObject(By.res("side_menu_button"))?.click()
                device.wait(Until.hasObject(settings), 5_000)
            }
        }
        (device.findObject(settings) ?: failWithScreen("student-menu", "no Settings in the menu")).click()
        (device.wait(Until.findObject(By.res("settings_row_privacyControls")), 15_000)
            ?: failWithScreen("student-settings", "Settings has no Privacy Controls row")).click()
        val unblock = device.wait(Until.findObject(By.res("unblock_teacher_$teacher")), 30_000)
            ?: failWithScreen("student-blocked-list", "the blocked teacher is not listed in Privacy Controls")
        if (!device.hasObject(By.text("Lesson Teacher"))) {
            failWithScreen("student-blocked-name", "the blocked teacher is listed without their name")
        }
        unblock.click()
        if (!device.wait(Until.gone(By.res("unblock_teacher_$teacher")), 20_000)) {
            failWithScreen("student-unblocked", "the teacher stayed listed after unblocking")
        }
        waitFor(20_000) { if (backend.strings("users/${student.uid}/blockedTeachers/$teacher") == null) true else null }
            ?: fail("unblocking left the teacher on the blocked list")

        // Unblocked: home again, still signed in, and the next question
        // reaches the teacher, whose half declines it from its card.
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        if (!waitForStudentHome(60_000)) failWithScreen("student-home", "relaunching did not reach home")
        val unblockedQid = askAQuestion("Unblocked check - this must reach the teacher", student.uid, listOf(qid, blockedQid))
        waitFor(30_000) { if (backend.exists("teacherInvites/$teacher/$unblockedQid")) true else null }
            ?: failWithScreen("student-unblocked-invite", "the unblocked teacher was not sent the question")
        waitFor(90_000) { backend.strings("questions/$unblockedQid/invites/$teacher")?.get("response")?.takeIf { it == "decline" } }
            ?: fail("the teacher's half never declined the card, so it was never on their screen")
        device.findObject(By.res("search_details_cancel"))?.click()
    }

    /** Writes `text` on the Text tab, taps Find a teacher, and returns the
     *  new question, the first of the student's not in `known`. */
    private fun askAQuestion(text: String, studentUid: String, known: List<String>): String {
        repeat(4) {
            if (!device.hasObject(By.res("question_text"))) {
                device.wait(Until.findObject(By.res("question_home_mode_text")), 10_000)?.click()
                device.wait(Until.hasObject(By.res("question_text")), 5_000)
            }
        }
        type(text, into = "question_text")
        device.pressBack() // the keyboard
        (device.wait(Until.findObject(By.res("find_teacher")), 15_000)
            ?: failWithScreen("student-find", "no Find a teacher")).click()
        if (!device.wait(Until.hasObject(By.res("search_details_cancel")), 30_000)) {
            failWithScreen("student-search", "Find a teacher did not start a search")
        }
        return waitFor(20_000) { backend.documentIds("questions", "studentUid", studentUid).firstOrNull { it !in known } }
            ?: failWithScreen("student-question", "no question was created")
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
        if (sessionShots) Thread.sleep(2_000)
        shot("02-$side-lesson-start")
    }

    // Session screenshots, for scripts/ui-tests/run_session_screenshots.sh.
    // Off unless the run passes sessionShots=1, so the sanity run is unchanged.

    private val sessionShots: Boolean get() = args.getString("sessionShots") == "1"

    /** A picture of the screen, in files/ui-test/shots, for the script to pull. */
    private fun shot(name: String) {
        if (!sessionShots) return
        val dir = java.io.File(context.filesDir, "ui-test/shots").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "$name.png"))
    }

    /** One chat message, best effort: a lesson without a reachable field goes on. */
    private fun sendMessage(text: String) {
        device.findObject(By.res("session_tab_chat"))?.let { runCatching { it.click() } }
        val tagged = device.wait(Until.findObject(By.res("chat_message_field")), 10_000) ?: return
        val field: UiObject2 = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        runCatching {
            field.click()
            field.text = text
            device.wait(Until.findObject(By.res("chat_send_button")), 5_000)?.click()
            Thread.sleep(500)
            // Back closes the keyboard; with no keyboard up it would leave the lesson.
            if (device.executeShellCommand("dumpsys input_method").contains("mInputShown=true")) device.pressBack()
        }
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
