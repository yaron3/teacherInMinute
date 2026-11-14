package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-22: in a lesson's chat, the message input stays on screen as the thread
 * grows, and with the keyboard up.
 *
 * The teacher accepts a seeded text question (no audio needed), then the
 * student's side is played by writing messages straight into the lesson's
 * thread on the emulators.
 */
@RunWith(AndroidJUnit4::class)
class ChatKeyboardTest : ProTeacherEmulatorTest() {

    @Test
    fun theInputStaysOnScreenWithALongThreadAndTheKeyboard() {
        openLesson()

        repeat(15) { i -> studentSays("Student message number ${i + 1} in a long thread") }
        Thread.sleep(3_000)
        shot("it22-long-thread")

        val field = device.wait(Until.findObject(By.res("chat_message_field")), 5_000)
        assertNotNull("the message input is not on screen once the thread grows", field)

        assertTrue("the lesson's bottom bar is missing before typing", device.hasObject(By.text("Session Time")))

        field!!.click()
        Thread.sleep(2_000)
        shot("it22-keyboard-up")
        val typing = device.wait(Until.findObject(By.res("chat_message_field")), 5_000)
        assertNotNull("the message input is not on screen with the keyboard up", typing)
        // The whole input, border included, sits above the keyboard.
        val keyboardTop = device.findObjects(By.pkg("com.google.android.inputmethod.latin"))
            .minOfOrNull { it.visibleBounds.top }
        assertNotNull("could not find the keyboard on screen", keyboardTop)
        assertTrue(
            "the message input runs under the keyboard (input bottom ${typing!!.visibleBounds.bottom}, keyboard top $keyboardTop)",
            typing.visibleBounds.bottom <= keyboardTop!!
        )
        // The bar stays behind the keyboard rather than riding up on top of it.
        assertTrue(
            "the lesson's bottom bar rose with the keyboard",
            device.wait(Until.gone(By.text("Session Time")), 5_000)
        )

        // Back puts the keyboard away but leaves the field focused; the bar,
        // with the timer and media controls, comes back all the same.
        device.pressBack()
        Thread.sleep(1_500)
        shot("it22-keyboard-closed")
        assertTrue(
            "the lesson's bottom bar stayed hidden after the keyboard closed",
            device.wait(Until.hasObject(By.text("Session Time")), 5_000)
        )
        // ...and does not cover the input.
        val closed = device.findObject(By.res("chat_message_field"))
        val timer = device.findObject(By.text("Session Time"))
        assertNotNull("the message input is gone after the keyboard closed", closed)
        assertTrue(
            "the bottom bar covers the input (input bottom ${closed!!.visibleBounds.bottom}, timer top ${timer.visibleBounds.top})",
            closed.visibleBounds.bottom <= timer.visibleBounds.top
        )
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
    }

    /** A message from the student, as their app writes it. */
    private fun studentSays(text: String) {
        val id = "m-${System.nanoTime()}"
        backend.put(
            "questions/$qid/messages/$id",
            JSONObject()
                .put("text", text)
                .put("senderUid", student.uid)
                .put("senderRole", "student")
                .put("createdAt", System.currentTimeMillis())
        )
        Thread.sleep(150)
    }

    /** A screenshot and the window hierarchy, where `adb pull` can reach them. */
    private fun shot(name: String) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    private fun failWith(message: String): Nothing {
        shot("it22-failure")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
