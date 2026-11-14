package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-29: the dashboard header's bell stays where it is after the messages
 * panel is opened and closed. It used to drift toward the centre.
 *
 * The Android twin of the iOS ProTeacherHeaderUITests. Signs in as the
 * emulator teacher, so it needs the local Firebase emulators and a debug build.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherHeaderTest : ProTeacherEmulatorTest() {

    override val signsInAtStart = false

    @Test
    fun theBellStaysPutAfterTheMessagesPanelCloses() {
        signIn()

        val bell = device.wait(Until.findObject(By.res("messages_button")), 30_000)
            ?: failWith("the bell never appeared on the dashboard header")
        val before = bell.visibleBounds
        shot("it29-header-before")

        bell.click()
        device.waitForIdle()
        Thread.sleep(1_500)
        shot("it29-messages-panel-open")

        device.pressBack()
        val bellAfter = device.wait(Until.findObject(By.res("messages_button")), 15_000)
            ?: failWith("the bell did not come back after closing the messages panel")
        Thread.sleep(1_000)
        shot("it29-header-after")

        val after = bellAfter.visibleBounds
        assertTrue("the bell moved horizontally after closing the panel (${before.left} -> ${after.left})", kotlin.math.abs(before.left - after.left) <= 2)
        assertTrue("the bell moved vertically after closing the panel (${before.top} -> ${after.top})", kotlin.math.abs(before.top - after.top) <= 2)
        assertTrue("the bell changed size after closing the panel", kotlin.math.abs(before.width() - after.width()) <= 2)
    }

    /** Saves a screenshot where `adb pull` can reach it, under the app's external files. */
    private fun shot(name: String) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        device.takeScreenshot(java.io.File(dir, "$name.png"))
        java.io.File(dir, "$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
    }

    private fun failWith(message: String): Nothing {
        shot("it29-failure")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
