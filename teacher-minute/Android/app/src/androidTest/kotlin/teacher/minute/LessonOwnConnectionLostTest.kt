package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.util.regex.Pattern

/**
 * IT-36: the phone that loses its own connection mid-lesson says so, stops its
 * timer, and ends the lesson itself if the connection is not back within the
 * grace period. Before, it heard nothing from anyone and its timer ran on.
 *
 *  1. The teacher accepts a seeded text question, and the lesson is marked
 *     started so the app keeps its presence.
 *  2. Airplane mode goes on. The offline banner appears and the timer stops.
 *  3. About 35 seconds later the lesson closes on this phone.
 *  4. Back online, the lesson is over in the backend too.
 *
 * Runs on the local Firebase emulators; see ProTeacherAcceptRaceTest for how.
 */
@RunWith(AndroidJUnit4::class)
class LessonOwnConnectionLostTest : ProTeacherEmulatorTest() {

    private val timerPattern: Pattern = Pattern.compile("^\\d{1,2}:\\d{2}$")

    @Test
    fun aPhoneThatGoesOfflineStopsItsTimerAndEndsTheLesson() {
        openStartedLesson()
        // Long enough for presence to be kept and the connection read as up.
        Thread.sleep(5_000)

        try {
            setAirplaneMode(true)

            assertTrue(
                "no offline banner after the network went: ${screenText()}",
                device.wait(Until.hasObject(By.res("session_banner_self_reconnecting")), 20_000)
            )
            shot("it36-offline-banner")

            val stopped = timerTexts()
            Thread.sleep(3_000)
            assertEquals("the timer kept running while offline", stopped, timerTexts())

            assertTrue(
                "the lesson did not close on this phone after the grace period: ${screenText()}",
                device.wait(Until.gone(By.res("chat_message_field")), 60_000)
            )
            shot("it36-ended-offline")
        } finally {
            setAirplaneMode(false)
        }

        // Back online: the lesson is over in the backend as well, whichever of
        // the app's endLesson and the backend's endLostLesson got there first.
        val deadline = System.currentTimeMillis() + 90_000
        var live = true
        while (live && System.currentTimeMillis() < deadline) {
            live = runCatching { backend.exists("questions/$qid") }.getOrDefault(true)
            if (live) Thread.sleep(2_000)
        }
        assertTrue("the lesson is still live in the backend after the phone came back", !live)
    }

    /** Accepts a seeded text question and marks the lesson started. */
    private fun openStartedLesson() {
        seedQuestion()
        val accept = device.wait(Until.findObject(acceptSelector()), 30_000)
            ?: failWith("the invite card never appeared")
        accept.click()
        if (device.wait(Until.findObject(By.res("chat_message_field")), 60_000) == null) {
            failWith("accepting did not open the lesson's chat")
        }
        // Both sides finished connecting: the session is counted from here,
        // and presence is kept only once it has started.
        backend.patch("questions/$qid", JSONObject().put("startedAt", System.currentTimeMillis()))
        if (!device.wait(Until.hasObject(By.pkg(context.packageName).text(timerPattern)), 20_000)) {
            failWith("the lesson's timer never showed")
        }
    }

    private fun timerTexts(): List<String> =
        // The app's own: the status bar's clock matches the pattern too.
        device.findObjects(By.pkg(context.packageName).text(timerPattern)).map { it.text }.sorted()

    private fun setAirplaneMode(on: Boolean) {
        device.executeShellCommand("cmd connectivity airplane-mode ${if (on) "enable" else "disable"}")
        Thread.sleep(1_000)
    }

    /** A screenshot and the window hierarchy, where `adb pull` can reach them. */
    private fun shot(name: String) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    private fun failWith(message: String): Nothing {
        shot("it36-failure")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
