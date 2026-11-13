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
class ProTeacherAcceptRaceTest : ProTeacherEmulatorTest() {

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
}
