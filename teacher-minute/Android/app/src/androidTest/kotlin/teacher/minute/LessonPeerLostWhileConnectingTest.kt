package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-38: a student whose app is killed while the lesson is still connecting
 * no longer leaves the teacher waiting until the 5-minute check for lessons
 * that never started.
 *
 *  1. The teacher accepts a seeded question and stays on the connecting
 *     screen, keeping its presence there (new: it used to start only once the
 *     lesson had started).
 *  2. The student's side is marked cut off, as the database server does when
 *     its app is swiped away.
 *  3. After the 30-second grace period the backend writes the lesson off as
 *     the student's, billing nothing, and the teacher is told the student left.
 *
 * Runs on the local Firebase emulators; see ProTeacherAcceptRaceTest for how.
 */
@RunWith(AndroidJUnit4::class)
class LessonPeerLostWhileConnectingTest : ProTeacherEmulatorTest() {

    @Test
    fun aStudentLostWhileConnectingEndsTheLessonForNothing() {
        // Still connecting: no lesson yet, so the write-off applies.
        seedQuestion(started = false)
        val accept = device.wait(Until.findObject(acceptSelector()), 30_000)
            ?: failWith("the invite card never appeared")
        accept.click()

        assertTrue(
            "the teacher kept no presence while connecting",
            waitUntil(30_000) {
                (backend.value("lessonPresence/$qid/teacher/connections") as? JSONObject)?.length()?.let { it > 0 } == true
            }
        )

        // What the database server writes when the student's app goes away.
        backend.put("lessonPresence/$qid/student", JSONObject().put("lostAt", System.currentTimeMillis()))

        assertTrue(
            "the teacher was not told the student left: ${screenText()}",
            waitUntil(75_000) { cancelledDialogShown() }
        )
        shot("it38-student-left")

        val fields = backend.fields("questions/$qid")
        assertEquals("status", "cancelled", stringValue(fields, "status"))
        assertEquals(
            "the backend did not write it off as the student's; the app's own fallback ended it",
            "student",
            stringValue(fields, "endedBy")
        )
        assertEquals("billed", "0", fields?.optJSONObject("billedSeconds")?.optString("integerValue"))
    }

    private fun waitUntil(timeoutMs: Long, condition: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (runCatching(condition).getOrDefault(false)) return true
            Thread.sleep(1_000)
        }
        return false
    }

    private fun stringValue(fields: JSONObject?, key: String): String? =
        fields?.optJSONObject(key)?.optString("stringValue")?.takeIf { it.isNotEmpty() }

    /** A screenshot and the window hierarchy, where `adb pull` can reach them. */
    private fun shot(name: String) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    private fun failWith(message: String): Nothing {
        shot("it38-failure")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
