package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-41: the system Back button during a lesson asks whether to end it, the
 * question the End control asks, instead of leaving the app.
 *
 *  1. Back opens "Are you sure you want to end this session?". The app stays
 *     in front and the lesson keeps running.
 *  2. Back again closes the question, as its Cancel does.
 *  3. Back, then "End session", ends the lesson.
 *
 * The teacher accepts a seeded text question, as in ChatKeyboardTest. Runs on
 * the local Firebase emulators; see ProTeacherAcceptRaceTest for how.
 */
@RunWith(AndroidJUnit4::class)
class LessonSystemBackTest : ProTeacherEmulatorTest() {

    // The new accounts the suite signs in with use the app in English.
    private val confirmMessages = listOf("Are you sure you want to end this session?")
    private val endLabels = listOf("End session")

    @Test
    fun backAsksBeforeEndingTheLesson() {
        openLesson()

        device.pressBack()
        assertTrue("Back did not ask whether to end the lesson: ${screenText()}", waitForConfirm(true))
        assertEquals("Back left the app", context.packageName, device.currentPackageName)
        assertTrue("the lesson closed behind the question", device.hasObject(By.res("chat_message_field")))
        shot("it41-back-asks")

        device.pressBack()
        assertTrue("a second Back did not close the question: ${screenText()}", waitForConfirm(false))
        assertEquals("the second Back left the app", context.packageName, device.currentPackageName)
        assertTrue("the lesson is gone after closing the question", device.hasObject(By.res("chat_message_field")))

        device.pressBack()
        assertTrue("Back did not ask again: ${screenText()}", waitForConfirm(true))
        val end = endLabels.firstNotNullOfOrNull { device.findObject(By.text(it)) }
            ?: failWith("the question has no End session button")
        end.click()
        assertTrue(
            "confirming did not end the lesson: ${screenText()}",
            device.wait(Until.gone(By.res("chat_message_field")), 30_000)
        )
        shot("it41-ended")
    }

    private fun waitForConfirm(shown: Boolean): Boolean {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            val visible = confirmMessages.any { device.hasObject(By.text(it)) }
            if (visible == shown) return true
            Thread.sleep(250)
        }
        return false
    }

    /** Accepts a seeded text question and waits for the lesson's chat. */
    private fun openLesson() {
        seedQuestion()
        val accept = device.wait(Until.findObject(acceptSelector()), 30_000)
            ?: failWith("the invite card never appeared")
        accept.click()
        if (device.wait(Until.findObject(By.res("chat_message_field")), 60_000) == null) {
            failWith("accepting did not open the lesson's chat")
        }
        // The chat field takes focus as the lesson opens; with the keyboard up
        // the first Back belongs to the keyboard, not to the lesson.
        Thread.sleep(1_500)
        if (device.findObjects(By.pkg("com.google.android.inputmethod.latin")).isNotEmpty()) {
            device.pressBack()
            Thread.sleep(1_000)
        }
    }

    /** A screenshot and the window hierarchy, where `adb pull` can reach them. */
    private fun shot(name: String) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    private fun failWith(message: String): Nothing {
        shot("it41-failure")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
