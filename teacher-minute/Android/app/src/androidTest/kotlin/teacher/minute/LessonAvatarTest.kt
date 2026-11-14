package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-31: with profile pictures shared, each side of a lesson gets the other's
 * picture. The teacher here is the app; the student is played on the emulators.
 *
 * Accepting goes through the real acceptInvite function, which snapshots both
 * names and pictures onto the question. The lesson reads the other side's
 * picture from there: Firestore rules keep a user from reading the other's
 * profile directly.
 */
@RunWith(AndroidJUnit4::class)
class LessonAvatarTest : ProTeacherEmulatorTest() {

    override val signsInAtStart = false

    private val studentPhoto = "https://teacher-in-a-moment.web.app/logo.png"
    private val teacherPhoto = "https://teacher-in-a-moment.web.app/logo-mark.png"

    @Test
    fun theTeacherGetsTheStudentsPictureInTheLesson() {
        backend.merge("users/${student.uid}", mapOf("profileImageURL" to studentPhoto, "showProfileImage" to true))
        backend.merge("users/${appTeacher.uid}", mapOf("profileImageURL" to teacherPhoto, "showProfileImage" to true))
        signIn()

        seedQuestion()
        val accept = device.wait(Until.findObject(acceptSelector()), 30_000)
            ?: failWith("the invite card never appeared")
        accept.click()
        if (device.wait(Until.findObject(By.res("chat_message_field")), 60_000) == null) {
            failWith("accepting did not open the lesson's chat")
        }
        // A message from the student, whose bubble carries the student's picture.
        backend.put(
            "questions/$qid/messages/m-${System.nanoTime()}",
            org.json.JSONObject()
                .put("text", "Hi, this is the student")
                .put("senderUid", student.uid)
                .put("senderRole", "student")
                .put("createdAt", System.currentTimeMillis())
        )
        // The field takes focus as the lesson opens; the bottom bar with both
        // portraits only shows once the keyboard is down. Back only while the
        // keyboard is up, or it would leave the lesson.
        if (device.wait(Until.hasObject(By.pkg("com.google.android.inputmethod.latin")), 3_000)) {
            device.pressBack()
        }
        Thread.sleep(5_000)
        shot("it31-lesson-teacher-side")

        val question = backend.strings("questions/$qid") ?: emptyMap()
        println("[LessonAvatarTest] question images: student=${question["studentImageURL"]} teacher=${question["teacherImageURL"]}")
        assertEquals("the question carries no student picture for the teacher", studentPhoto, question["studentImageURL"])
        assertEquals("the question carries no teacher picture for the student", teacherPhoto, question["teacherImageURL"])

        // What the lesson screen is handed on Android: the bridge used to leave
        // both pictures out, so the other side's avatar stayed blank.
        val details = org.json.JSONObject(AndroidChatManager.fetchSessionDetailsJson(qid))
        assertEquals("the lesson is not given the student's picture", studentPhoto, details.optString("studentImageURL"))
        assertEquals("the lesson is not given the teacher's picture", teacherPhoto, details.optString("teacherImageURL"))
    }

    private fun shot(name: String) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    private fun failWith(message: String): Nothing {
        shot("it31-failure")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
