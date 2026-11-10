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
 * What every Pro Teacher UI test on the local Firebase emulators shares — the
 * Android twin of the iOS ProTeacherEmulatorTestCase: two new teachers and a
 * student on the emulators, Pro Teacher signed in as the first teacher on its
 * dashboard, a way to seed or ask a question, and the waits that keep
 * UiAutomator steady. The suites are ProTeacherAcceptRaceTest and
 * ProTeacherDispatchTest; see the first for how to run them.
 */
abstract class ProTeacherEmulatorTest {
    protected val instrumentation = InstrumentationRegistry.getInstrumentation()
    protected val device = UiDevice.getInstance(instrumentation)
    protected val context: Context = ApplicationProvider.getApplicationContext()
    protected val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)

    protected lateinit var appTeacher: EmulatorBackend.Account
    protected lateinit var otherTeacher: EmulatorBackend.Account
    protected lateinit var student: EmulatorBackend.Account
    protected var qid = ""

    protected val topic = "algebra"
    protected val questionText = "Emulator race: solve 2x + 3 = 11"

    /** The "taken" dialog's message in either language. */
    /** The "student cancelled" dialog's title, in either language. */
    protected val cancelledMessages = listOf("The student cancelled the session", "התלמיד/ה ביטל/ה את השיעור")

    protected val takenMessages = listOf("Another teacher already answered it", "מורה אחר/ת כבר ענה/תה עליה")

    /** False for a suite that signs in itself, or not at all. */
    protected open val signsInAtStart = true

    @Before
    fun setUpScene() {
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
        // Enough minutes for createQuestion, which refuses fewer than two.
        backend.merge(
            "users/${student.uid}",
            mapOf("role" to "student", "fullName" to "Race Student", "remainingMinutes" to 30)
        )

        // The test runs in the app's own process: start from signed out, with
        // the notification prompt answered so it never covers a control.
        FirebaseAuth.getInstance().signOut()
        if (Build.VERSION.SDK_INT >= 33) {
            instrumentation.uiAutomation.grantRuntimePermission(
                context.packageName, android.Manifest.permission.POST_NOTIFICATIONS
            )
        }
        launchApp()
        openLoginForm()
        if (signsInAtStart) signIn()
    }

    /** From the welcome screen to the login form. */
    protected fun openLoginForm() {
        // A tap while the welcome screen is still animating in does nothing.
        repeat(5) {
            if (device.hasObject(By.res("email_input"))) return@repeat
            device.wait(Until.findObject(By.res("welcome_log_in")), 30_000)?.click()
            device.wait(Until.hasObject(By.res("email_input")), 5_000)
        }
        assertNotNull("the login form never opened", device.wait(Until.findObject(By.res("email_input")), 10_000))
    }

    protected fun submitLogin(email: String, password: String) {
        type(email, into = "email_input")
        type(password, into = "password_input")
        device.findObject(By.res("login_submit")).click()
    }

    /** Signs in as the app's teacher, from the login form to the dashboard. */
    protected fun signIn() {
        submitLogin(appTeacher.email, appTeacher.password)
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
    protected fun capture(name: String) {
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

    // Scene

    /** A searching question sent to both teachers, cards delivered. */
    protected fun seedQuestion() {
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

    // Real dispatch

    /**
     * Leaves exactly the two test teachers online, so a question asked through
     * the real createQuestion reaches them and nobody else. The app's teacher
     * went online by itself at launch.
     */
    protected fun prepareRealDispatch() {
        for (uid in backend.childKeys("teachers")) {
            if (uid != appTeacher.uid && uid != otherTeacher.uid) {
                backend.patch("teachers/$uid", JSONObject().put("status", "offline"))
            }
        }
        backend.put(
            "teachers/${otherTeacher.uid}",
            JSONObject().put("status", "online").put("subjects", org.json.JSONArray(listOf(topic)))
        )
        // The app can take half a minute: after signing in it sets its
        // presence up twice, and the second pass writes offline first.
        var online = false
        repeat(60) {
            if (!online) {
                online = backend.value("teachers/${appTeacher.uid}/status") == "online"
                if (!online) Thread.sleep(1_000)
            }
        }
        assertTrue("the app's teacher never went online", online)
    }

    /** The student asks, through the real createQuestion and dispatch. */
    protected fun ask(): String {
        val outcome = backend.call(
            "createQuestion", student,
            JSONObject().put("topic", topic).put("text", questionText).put("conversationType", "text")
        )
        val asked = outcome.result?.optString("questionId").orEmpty()
        assertTrue("createQuestion: $outcome", asked.isNotEmpty())
        qid = asked
        return asked
    }

    /** Waits until the database holds `teacher`'s invite card for `question`. */
    protected fun waitForInvite(teacher: EmulatorBackend.Account, question: String, timeoutMs: Long = 20_000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (backend.exists("teacherInvites/${teacher.uid}/$question")) return true
            Thread.sleep(500)
        }
        return false
    }

    protected fun declineSelector() = By.res("invite_decline_$qid")

    protected fun cancelledDialogShown(): Boolean = cancelledMessages.any { device.hasObject(By.textContains(it)) }

    protected fun card(): JSONObject = JSONObject()
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

    protected fun launchApp() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
    }

    /**
     * SkipUI puts the identifier on a container; the text field itself is an
     * EditText inside it, and only that takes text.
     */
    protected fun type(text: String, into: String) {
        val tagged = device.findObject(By.res(into))
        assertNotNull("no $into", tagged)
        val field = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    /** This question's Accept; the incoming-question overlay may repeat it. */
    protected fun acceptSelector() = By.res("invite_accept_$qid")

    protected fun takenDialogShown(): Boolean = takenMessages.any { device.hasObject(By.textContains(it)) }

    /** Every text on screen, for a failure message. An element that goes away
     *  while it is being read is skipped. */
    protected fun screenText(): String =
        device.findObjects(By.textContains(""))
            .mapNotNull { runCatching { it.text }.getOrNull() }
            .filter { it.isNotBlank() }
            .joinToString(" | ")
}
