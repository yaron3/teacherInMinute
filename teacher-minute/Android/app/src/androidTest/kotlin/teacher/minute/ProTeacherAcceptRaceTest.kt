package teacher.minute

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Date
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Pro Teacher losing the race for a question, on Android, against the real
 * backend running on the local Firebase emulators. QA test plan: AND-D-13,
 * AND-D-14, AND-D-15. The twin of the iOS `ProTeacherAcceptRaceUITests`, using
 * the same accessibility identifiers.
 *
 *  1. Another teacher accepts while the card is up: it closes by itself, with
 *     no dialog.
 *  2. The teacher taps a card that is already stale: the app says the question
 *     is gone and drops the card.
 *  3. Both accept at the same moment: whoever wins, the app ends in the right
 *     state.
 *
 * Each test signs in as a brand-new teacher and plays the other teacher itself,
 * through the real `acceptInvite`. The question is written straight into the
 * emulators, already sent to both teachers, so dispatch stands down.
 *
 * Running it, with the emulators up (`npm --prefix backend/Firebase/functions
 * run emulators:app`, Java 21+) and an Android emulator booted:
 *
 *     ./gradlew :app:connectedTeacherDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=teacher.minute.ProTeacherAcceptRaceTest
 *
 * Without the emulators every test is skipped.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherAcceptRaceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)

    private lateinit var appTeacher: EmulatorBackend.Account
    private lateinit var otherTeacher: EmulatorBackend.Account
    private lateinit var student: EmulatorBackend.Account
    private var qid = ""

    private val topic = "algebra"
    private val questionText = "Emulator race: solve 2x + 3 = 11"

    /** The "taken" dialog's message in either language. */
    private val takenMessages = listOf("Another teacher already answered it", "מורה אחר/ת כבר ענה/תה עליה")

    @Before
    fun signInAsNewTeacher() {
        assumeTrue("Firebase emulators not running", backend.isRunning())
        assumeTrue("needs a debug build on the emulators", AndroidFirebaseEmulator.host != null)

        appTeacher = backend.createAccount("race.app-teacher")
        otherTeacher = backend.createAccount("race.other-teacher")
        student = backend.createAccount("race.student")
        for ((account, name) in listOf(appTeacher to "Race App Teacher", otherTeacher to "Race Other Teacher")) {
            backend.merge(
                "users/${account.uid}",
                mapOf(
                    "role" to "teacher",
                    "fullName" to name,
                    "phoneNumber" to "+972500000000",
                    "subjectSelections" to mapOf("math" to listOf(topic)),
                )
            )
        }
        backend.merge("users/${student.uid}", mapOf("role" to "student", "fullName" to "Race Student"))

        // The test runs in the app's own process: start from signed out, with
        // the notification prompt answered so it never covers a control.
        FirebaseAuth.getInstance().signOut()
        if (Build.VERSION.SDK_INT >= 33) {
            instrumentation.uiAutomation.grantRuntimePermission(
                context.packageName, android.Manifest.permission.POST_NOTIFICATIONS
            )
        }
        launchApp()

        // A tap while the welcome screen is still animating in does nothing.
        repeat(5) {
            if (device.hasObject(By.res("email_input"))) return@repeat
            device.wait(Until.findObject(By.res("welcome_log_in")), 30_000)?.click()
            device.wait(Until.hasObject(By.res("email_input")), 5_000)
        }
        assertNotNull("the login form never opened", device.wait(Until.findObject(By.res("email_input")), 10_000))
        type(appTeacher.email, into = "email_input")
        type(appTeacher.password, into = "password_input")
        device.findObject(By.res("login_submit")).click()

        if (!device.wait(Until.hasObject(By.res("availability_toggle")), 90_000)) {
            capture("sign-in")
            fail("signing in did not reach the teacher dashboard: ${screenText()}")
        }
    }

    /**
     * Saves a screenshot and the window hierarchy to the app's files
     * (`adb shell run-as com.yaronj.tim ls files/ui-test`), for a failure that
     * needs seeing.
     */
    private fun capture(name: String) {
        val dir = java.io.File(context.filesDir, "ui-test").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    @After
    fun closeQuestion() {
        // A question left searching would be backfilled to the next test's
        // teacher the moment it comes online.
        if (qid.isNotEmpty()) runCatching { backend.merge("questions/$qid", mapOf("status" to "unanswered")) }
    }

    /** AND-D-13: another teacher takes the question while its card is up. */
    @Test
    fun cardClosesWhenAnotherTeacherAccepts() {
        seedQuestion()
        assertTrue("the invite card never appeared", device.wait(Until.hasObject(acceptSelector()), 30_000))

        backend.call("acceptInvite", otherTeacher, JSONObject().put("questionId", qid))
        assertEquals(otherTeacher.uid, backend.strings("questions/$qid")?.get("acceptedByTeacher"))

        assertTrue("the card stayed on screen", device.wait(Until.gone(acceptSelector()), 15_000))
        Thread.sleep(2_000)
        assertFalse("a dialog appeared although the teacher never tapped", device.hasObject(By.res("dialog_confirm_button")))
    }

    /** AND-D-15: the teacher taps a card another teacher has already taken. */
    @Test
    fun tappingAStaleCardSaysTheQuestionIsTaken() {
        seedQuestion()
        assertTrue("the invite card never appeared", device.wait(Until.hasObject(acceptSelector()), 30_000))

        backend.call("acceptInvite", otherTeacher, JSONObject().put("questionId", qid))
        assertEquals(otherTeacher.uid, backend.strings("questions/$qid")?.get("acceptedByTeacher"))
        assertTrue("the card did not close after the other accept", device.wait(Until.gone(acceptSelector()), 15_000))

        // The removal arriving late, as on a weak network.
        backend.put("teacherInvites/${appTeacher.uid}/$qid", card())
        val stale = device.wait(Until.findObject(acceptSelector()), 15_000)
        assertNotNull("the stale card was not shown", stale)
        stale.click()

        assertTrue("no dialog after accepting a taken question", device.wait(Until.hasObject(By.res("dialog_confirm_button")), 20_000))
        assertTrue("the dialog does not say the question was taken: ${screenText()}", takenDialogShown())
        assertTrue("the stale card stayed after the refusal", device.wait(Until.gone(acceptSelector()), 5_000))

        assertEquals(otherTeacher.uid, backend.strings("questions/$qid")?.get("acceptedByTeacher"))
        assertEquals("pending", backend.strings("questions/$qid/invites/${appTeacher.uid}")?.get("response"))
        device.findObject(By.res("dialog_confirm_button")).click()
    }

    /** AND-D-14: both teachers accept at the same moment. */
    @Test
    fun simultaneousAcceptEndsInOneConsistentState() {
        seedQuestion()
        val accept: UiObject2? = device.wait(Until.findObject(acceptSelector()), 30_000)
        assertNotNull("the invite card never appeared", accept)
        val point = accept!!.visibleCenter

        var otherOutcome: EmulatorBackend.CallOutcome? = null
        val other = thread { otherOutcome = backend.call("acceptInvite", otherTeacher, JSONObject().put("questionId", qid)) }
        // Tapped by position: if the card goes first, the tap lands on the dashboard.
        device.click(point.x, point.y)
        other.join(60_000)

        var winner: String? = null
        repeat(20) {
            winner = backend.strings("questions/$qid")?.get("acceptedByTeacher")
            if (winner != null) return@repeat
            Thread.sleep(1_000)
        }
        val appWon = winner == appTeacher.uid
        println("[ProTeacherAcceptRaceTest] race won by ${if (appWon) "the app" else "the other teacher"} other=$otherOutcome")

        assertTrue("nobody got the question", winner == appTeacher.uid || winner == otherTeacher.uid)
        assertTrue("the card stayed on screen after the race", device.wait(Until.gone(acceptSelector()), 15_000))

        if (appWon) {
            assertFalse("both teachers were told they got the question", otherOutcome?.succeeded ?: true)
            assertEquals("question_unavailable", otherOutcome?.reason)
            Thread.sleep(2_000)
            assertFalse("the winning app said the question was taken", takenDialogShown())
        } else {
            Thread.sleep(3_000)
            if (device.hasObject(By.res("dialog_confirm_button"))) {
                assertTrue("the losing app showed something other than \"already taken\": ${screenText()}", takenDialogShown())
            }
            assertEquals("pending", backend.strings("questions/$qid/invites/${appTeacher.uid}")?.get("response"))
        }
    }

    // Scene

    /** A searching question sent to both teachers, cards delivered. */
    private fun seedQuestion() {
        qid = "race-${UUID.randomUUID().toString().take(8)}"
        val now = Date()
        val expires = Date(now.time + 180_000)
        for (teacher in listOf(appTeacher, otherTeacher)) {
            backend.merge(
                "questions/$qid/invites/${teacher.uid}",
                mapOf("teacherUid" to teacher.uid, "response" to "pending", "wave" to 1, "invitedAt" to now, "expiresAt" to expires)
            )
        }
        backend.merge(
            "questions/$qid",
            mapOf(
                "studentUid" to student.uid,
                "status" to "searching",
                "topic" to topic,
                "text" to questionText,
                "conversationType" to "text",
                "dispatchWave" to 1,
                "alreadyInvited" to listOf(appTeacher.uid, otherTeacher.uid),
                // The Cloud Tasks emulator runs the abandoned-lesson check at
                // once instead of minutes later; a student already in a started
                // lesson keeps it from writing the lesson off.
                "joinedParticipants" to listOf(student.uid),
                "lessonId" to "$qid-lesson",
                "createdAt" to now,
                "updatedAt" to now,
            )
        )
        for (teacher in listOf(appTeacher, otherTeacher)) backend.put("teacherInvites/${teacher.uid}/$qid", card())
    }

    private fun card(): JSONObject = JSONObject()
        .put("questionId", qid)
        .put("topic", topic)
        .put("text", questionText)
        .put("expiresAt", System.currentTimeMillis() + 180_000)
        .put("wave", 1)
        .put("studentId", student.uid)
        .put("studentName", "Race Student")
        .put("conversationType", "text")
        .put("pricePerMinuteCents", 50)

    // App

    private fun launchApp() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
    }

    /**
     * SkipUI puts the identifier on a container; the text field itself is an
     * EditText inside it, and only that takes text.
     */
    private fun type(text: String, into: String) {
        val tagged = device.findObject(By.res(into))
        assertNotNull("no $into", tagged)
        val field = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    /** This question's Accept; the incoming-question overlay may repeat it. */
    private fun acceptSelector() = By.res("invite_accept_$qid")

    private fun takenDialogShown(): Boolean = takenMessages.any { device.hasObject(By.textContains(it)) }

    private fun screenText(): String =
        device.findObjects(By.textContains("")).mapNotNull { it.text }.filter { it.isNotBlank() }.joinToString(" | ")
}
