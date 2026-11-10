package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Date

/**
 * How questions reach Pro Teacher on Android, and leave it, against the real
 * backend on the local Firebase emulators — the twin of the iOS
 * ProTeacherDispatchUITests. QA test plan:
 *
 *   AND-D-16  the teacher declines: only their own card closes
 *   AND-D-19  the student cancels: the card closes; a late tap is told so
 *   AND-D-10  a question the student asks reaches the online teacher
 *   AND-D-21  a teacher who is in a lesson gets no invite
 *   AND-D-23  a teacher the student blocked gets no invite
 *
 * Run like ProTeacherAcceptRaceTest, with this class's name.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherDispatchTest : ProTeacherEmulatorTest() {

    /** AND-D-16: declining closes this teacher's card and nobody else's. */
    @Test
    fun decliningClosesOnlyThisTeachersCard() {
        seedQuestion()
        assertTrue("the invite card never appeared", device.wait(Until.hasObject(acceptSelector()), 30_000))

        val decline = device.wait(Until.findObject(declineSelector()), 10_000)
        assertNotNull("no Decline", decline)
        decline.click()
        assertTrue("the card stayed after declining", device.wait(Until.gone(acceptSelector()), 15_000))

        assertEquals("decline", backend.strings("questions/$qid/invites/${appTeacher.uid}")?.get("response"))
        assertEquals(
            "the other teacher's invite changed too",
            "pending", backend.strings("questions/$qid/invites/${otherTeacher.uid}")?.get("response")
        )
        assertTrue("the other teacher's card was removed too", backend.exists("teacherInvites/${otherTeacher.uid}/$qid"))
        assertEquals("declining ended the search", "searching", backend.strings("questions/$qid")?.get("status"))

        Thread.sleep(2_000)
        assertFalse("declining showed a dialog", device.hasObject(By.res("dialog_confirm_button")))
    }

    /** AND-D-19: the student cancels while the card is up. */
    @Test
    fun studentCancellingClosesTheCard() {
        seedQuestion()
        assertTrue("the invite card never appeared", device.wait(Until.hasObject(acceptSelector()), 30_000))

        val outcome = backend.call("cancelQuestion", student, JSONObject().put("questionId", qid))
        assertTrue("cancelQuestion: $outcome", outcome.succeeded)

        assertTrue("the card stayed after the student cancelled", device.wait(Until.gone(acceptSelector()), 15_000))
        assertFalse("the other teacher's card was not removed", backend.exists("teacherInvites/${otherTeacher.uid}/$qid"))
        Thread.sleep(2_000)
        assertFalse("a dialog appeared although the teacher never tapped", device.hasObject(By.res("dialog_confirm_button")))
    }

    /** AND-D-19: a tap on a card whose cancellation has not arrived yet is told so. */
    @Test
    fun tappingACardTheStudentCancelledSaysSo() {
        seedQuestion()
        assertTrue("the invite card never appeared", device.wait(Until.hasObject(acceptSelector()), 30_000))

        val outcome = backend.call("cancelQuestion", student, JSONObject().put("questionId", qid))
        assertTrue("cancelQuestion: $outcome", outcome.succeeded)
        assertTrue("the card did not close after the cancel", device.wait(Until.gone(acceptSelector()), 15_000))

        // The removal arriving late, as on a weak network.
        backend.put("teacherInvites/${appTeacher.uid}/$qid", card())
        val stale = device.wait(Until.findObject(acceptSelector()), 15_000)
        assertNotNull("the stale card was not shown", stale)
        stale.click()

        assertTrue("no dialog after accepting a cancelled question", device.wait(Until.hasObject(By.res("dialog_confirm_button")), 20_000))
        assertTrue("the dialog does not say the student cancelled: ${screenText()}", cancelledDialogShown())
        device.findObject(By.res("dialog_confirm_button")).click()
        Thread.sleep(3_000)
        assertFalse("the cancelled card came back", device.hasObject(acceptSelector()))
    }

    /** AND-D-10: a question the student asks reaches the online teacher. */
    @Test
    fun aQuestionAskedReachesTheOnlineTeacher() {
        prepareRealDispatch()
        val asked = ask()

        assertTrue("the asked question never reached the app", device.wait(Until.hasObject(acceptSelector()), 20_000))
        assertTrue("the other online teacher was not invited", waitForInvite(otherTeacher, asked))
        assertEquals("searching", backend.strings("questions/$asked")?.get("status"))
    }

    /** AND-D-21: a teacher who is in a lesson is not invited. */
    @Test
    fun aBusyTeacherGetsNoInvite() {
        prepareRealDispatch()
        backend.put(
            "teachers/${appTeacher.uid}/busy",
            JSONObject().put("questionId", "earlier-lesson").put("since", System.currentTimeMillis())
        )
        val asked = ask()

        assertTrue("dispatch did not run: the free teacher was not invited either", waitForInvite(otherTeacher, asked))
        Thread.sleep(5_000)
        assertFalse("the busy teacher was invited", backend.exists("teacherInvites/${appTeacher.uid}/$asked"))
        assertFalse("the busy teacher's app shows the question", device.hasObject(acceptSelector()))
    }

    /** AND-D-23: a teacher the student blocked is not invited. */
    @Test
    fun aBlockedTeacherGetsNoInvite() {
        prepareRealDispatch()
        // As blockTeacher records it after an earlier lesson.
        backend.merge(
            "users/${student.uid}/blockedTeachers/${appTeacher.uid}",
            mapOf(
                "teacherUid" to appTeacher.uid,
                "teacherName" to "Race App Teacher",
                "questionId" to "earlier-lesson",
                "blockedAt" to Date(),
            )
        )
        val asked = ask()

        assertTrue("dispatch did not run: the other teacher was not invited either", waitForInvite(otherTeacher, asked))
        Thread.sleep(5_000)
        assertFalse("the blocked teacher was invited", backend.exists("teacherInvites/${appTeacher.uid}/$asked"))
        assertFalse("the blocked teacher's app shows the question", device.hasObject(acceptSelector()))
    }
}
