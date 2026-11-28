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
        // The lesson opens with the field focused and the keyboard up, and
        // messages arriving leave it there: the field used to be a row of the
        // thread's lazy list, rebuilt — and unfocused — by every message.
        assertTrue("messages arriving closed the keyboard", keyboardIsUp())

        assertTrue("the lesson's bottom bar is missing before typing", device.hasObject(By.text("Session Time")))

        field!!.click()
        Thread.sleep(2_000)
        shot("it22-keyboard-up")
        val typing = device.wait(Until.findObject(By.res("chat_message_field")), 5_000)
        assertNotNull("the message input is not on screen with the keyboard up", typing)
        // The whole input, border included, sits above the keyboard.
        // Measured from what the keyboard draws and takes taps on — keys and
        // its toolbar. Gboard on Android 14 puts an empty strip about 23 px
        // tall above its toolbar, which would otherwise count as keyboard.
        val keyboardTop = device.findObjects(By.pkg("com.google.android.inputmethod.latin").clickable(true))
            .minOfOrNull { it.visibleBounds.top }
        assertNotNull("could not find the keyboard on screen", keyboardTop)
        assertTrue(
            "the message input runs under the keyboard (input bottom ${typing!!.visibleBounds.bottom}, keyboard top $keyboardTop)",
            typing.visibleBounds.bottom <= keyboardTop!!
        )
        // The lesson's controls ride up with the keyboard: right under the
        // input, above the keyboard.
        val typingTimer = device.wait(Until.findObject(By.text("Session Time")), 5_000)
        assertNotNull("the lesson's bottom bar is hidden while typing", typingTimer)
        assertTrue(
            "the bottom bar is not below the input (input bottom ${typing.visibleBounds.bottom}, timer top ${typingTimer!!.visibleBounds.top})",
            typing.visibleBounds.bottom <= typingTimer.visibleBounds.top
        )
        assertTrue(
            "the bottom bar is under the keyboard (timer bottom ${typingTimer.visibleBounds.bottom}, keyboard top $keyboardTop)",
            typingTimer.visibleBounds.bottom <= keyboardTop
        )

        // The keyboard stays until the user puts it away: a formula from the
        // other side used to close it.
        studentSays("\$\$x^2 + 1 = 5\$\$")
        Thread.sleep(2_000)
        shot("keyboard-after-formula")
        assertTrue("a formula from the student closed the keyboard", keyboardIsUp())
        assertNotNull(
            "the message input left the screen when the formula arrived",
            device.findObject(By.res("chat_message_field"))
        )

        // Enter sends, and the keyboard stays: it used to clear focus and send nothing.
        val draft = "Sent from the keyboard"
        device.findObject(By.res("chat_message_field")).text = draft
        device.pressEnter()
        assertTrue(
            "Enter on the keyboard did not send the message",
            device.wait(Until.hasObject(By.text(draft)), 10_000)
        )
        Thread.sleep(2_000)
        shot("keyboard-after-send")
        assertTrue("sending from the keyboard closed it", keyboardIsUp())

        // Back puts the keyboard away but leaves the field focused; the bar,
        // with the timer and media controls, stays.
        device.pressBack()
        Thread.sleep(1_500)
        shot("it22-keyboard-closed")
        assertTrue(
            "the lesson's bottom bar is gone after the keyboard closed",
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

    /**
     * A message that arrives while the teacher is building a formula on the
     * math pad leaves the formula alone: the pad is a row of the thread's lazy
     * list, rebuilt by every message, and it used to lose what was typed.
     */
    @Test
    fun aMessageArrivingKeepsTheFormulaBeingWritten() {
        openLesson()
        device.findObject(By.res("chat_math_button")).click()
        for (label in listOf("7", "+", "3")) {
            val key = device.wait(Until.findObject(By.clickable(true).hasDescendant(By.text(label))), 5_000)
                ?: failWith("the math pad has no $label key")
            key.click()
            Thread.sleep(300)
        }

        studentSays("A message while the teacher writes a formula")
        studentSays("And another one")
        Thread.sleep(2_000)
        shot("formula-after-messages")

        val send = device.wait(Until.findObject(By.res("math_editor_send")), 5_000)
            ?: failWith("the math pad's send button is not on screen")
        send.click()

        val deadline = System.currentTimeMillis() + 10_000
        var sent: String? = null
        while (sent == null && System.currentTimeMillis() < deadline) {
            val messages = backend.value("questions/$qid/messages") as? JSONObject
            sent = messages?.keys()?.asSequence()
                ?.map { messages.getJSONObject(it) }
                ?.firstOrNull { it.optString("senderRole") == "teacher" }
                ?.optString("text")
            if (sent == null) Thread.sleep(500)
        }
        shot("formula-sent")
        assertNotNull("the formula was lost when messages arrived: nothing was sent", sent)
        assertTrue("the formula sent is not the one typed: $sent", sent!!.replace(" ", "").contains("7+3"))
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

    private fun keyboardIsUp(): Boolean =
        device.findObjects(By.pkg("com.google.android.inputmethod.latin")).isNotEmpty()

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
