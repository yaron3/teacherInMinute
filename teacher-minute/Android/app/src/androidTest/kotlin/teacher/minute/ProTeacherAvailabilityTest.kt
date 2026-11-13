package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The dashboard's availability switch against the real backend on the local
 * Firebase emulators — the Android twin of the iOS
 * ProTeacherAvailabilityUITests. What the switch says, what teachers/{uid}
 * says and what students see in onlineTeachers must always agree. QA test
 * plan:
 *
 *   AND-P-01  switching on: status online, listed with the teacher's
 *             subjects, the card reads Available
 *   AND-P-02  switching off: unlisted, Not available, and a question asked
 *             afterwards sends this teacher nothing
 *   AND-P-09  editing subjects while online (from Profile; the dashboard
 *             offers it only offline): onlineTeachers carries the new subjects
 *   AND-P-10  flipping the switch several times: each flip sticks, and the
 *             card and the database agree after each one
 *
 * A teacher comes online by themselves on signing in. Runs in the Pro Teacher
 * flavor; see ProTeacherAcceptRaceTest for how.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherAvailabilityTest : ProTeacherEmulatorTest() {

    private val availableTitles = listOf("Available", "זמין")
    private val notAvailableTitles = listOf("Not available", "לא זמין")

    /** AND-P-01 and AND-P-02: off, then on again. */
    @Test
    fun switchingOffAndOnAgain() {
        expectState(online = true, "after signing in")

        flip()
        expectState(online = false, "after switching off")

        flip()
        expectState(online = true, "after switching on again")
        val subjects = backend.value("onlineTeachers/${appTeacher.uid}/subjects") as? JSONArray
        assertEquals("onlineTeachers lists the wrong subjects", listOf(topic), subjects?.let { list(it) })
    }

    /** AND-P-02: a teacher who switched off is sent nothing. */
    @Test
    fun aTeacherSwitchedOffGetsNoInvite() {
        prepareRealDispatch()
        flip()
        expectState(online = false, "after switching off")

        val asked = ask()

        assertTrue("the question reached nobody, so the test proves nothing", waitForInvite(otherTeacher, asked))
        assertFalse("a teacher who switched off got the question", waitForInvite(appTeacher, asked, timeoutMs = 5_000))
    }

    /** AND-P-09: new subjects reach students without switching off and on. */
    @Test
    fun editingSubjectsWhileOnlineUpdatesTheListing() {
        expectState(online = true, "after signing in")

        val added = addASubject()

        var listed = emptyList<String>()
        val deadline = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < deadline && added !in listed) {
            listed = (backend.value("onlineTeachers/${appTeacher.uid}/subjects") as? JSONArray)?.let { list(it) } ?: emptyList()
            if (added !in listed) Thread.sleep(500)
        }
        val presence = (backend.value("teachers/${appTeacher.uid}/subjects") as? JSONArray)?.let { list(it) } ?: emptyList()
        assertTrue("teachers/{uid}/subjects kept the old subjects: $presence", added in presence)
        assertTrue("onlineTeachers kept the old subjects: $listed", added in listed)
        assertTrue("onlineTeachers lost the subject the teacher kept: $listed", topic in listed)
        expectState(online = true, "after editing subjects")
    }

    /** AND-P-10: several flips, each one sticking. */
    @Test
    fun flippingRepeatedlyAlwaysAgrees() {
        expectState(online = true, "after signing in")
        var online = true
        for (flipNumber in 1..6) {
            flip()
            online = !online
            expectState(online, "after flip $flipNumber")
        }
    }

    // Steps

    private fun flip() {
        val toggle = device.wait(Until.findObject(By.res("availability_toggle")), 15_000)
            ?: failWith("toggle", "the availability switch never appeared")
        toggle.click()
    }

    /** Waits for the card, teachers/{uid} and onlineTeachers all to say
     *  `online`, then checks they still agree a moment later. */
    private fun expectState(online: Boolean, `when`: String) {
        val titles = if (online) availableTitles else notAvailableTitles
        var status: Any? = null
        var listed = false
        var shown = false
        val deadline = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < deadline) {
            status = backend.value("teachers/${appTeacher.uid}/status")
            listed = backend.exists("onlineTeachers/${appTeacher.uid}")
            shown = cardSays(titles)
            if ((status == "online") == online && listed == online && shown) break
            Thread.sleep(500)
        }
        if ((status == "online") != online || listed != online || !shown) {
            failWith("state", "${`when`}: expected ${if (online) "online" else "offline"}, got status=$status listed=$listed card=$shown")
        }
        // Still so after the writes have settled: no flip-back.
        Thread.sleep(2_000)
        val settled = backend.value("teachers/${appTeacher.uid}/status")
        val stillListed = backend.exists("onlineTeachers/${appTeacher.uid}")
        if ((settled == "online") != online || stillListed != online || !cardSays(titles)) {
            failWith("flip-back", "${`when`}: flipped back to status=$settled listed=$stillListed")
        }
    }

    /** Whether one of `titles` is on screen as a whole text. Compared after
     *  stripping direction marks, which right-to-left text can carry; not a
     *  contains-match, since "זמין" is inside "לא זמין". */
    private fun cardSays(titles: List<String>): Boolean {
        val marks = Regex("[\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]")
        val texts = device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }
            .map { it.replace(marks, "").trim() }
        return titles.any { it in texts }
    }

    /** Opens the subject editor from the Profile tab, adds one subject and
     *  saves, then goes back home; returns the added subject's key. */
    private fun addASubject(): String {
        tapId("tab_item_profile", "the Profile tab")
        val edit = findScrolling(By.res("profile_subjects_edit_button")) ?: failWith("profile", "no edit on Profile's subjects card")
        edit.click()
        if (!device.wait(Until.hasObject(By.res("teacher_subjects_continue")), 20_000)) failWith("editor", "the subject editor did not open")

        if (!device.wait(Until.hasObject(By.res(java.util.regex.Pattern.compile("subject_chip_.*"))), 5_000)) {
            device.findObject(By.res(java.util.regex.Pattern.compile("teacher_subject_area_.*")))?.click()
                ?: failWith("area", "no subject area to pick")
        }
        val other = device.wait(
            Until.findObject(By.res(java.util.regex.Pattern.compile("subject_chip_(?!${topic}$).*"))), 10_000
        ) ?: failWith("chip", "no other subject to add")
        val key = other.resourceName.substringAfterLast("subject_chip_")
        other.click()

        val save = findScrolling(By.res("teacher_subjects_continue")) ?: failWith("save", "no save in the editor")
        save.click()
        if (!device.wait(Until.gone(By.res("teacher_subjects_continue")), 20_000)) failWith("editor", "the subject editor did not close")
        tapId("tab_item_home", "the Home tab")
        println("[ProTeacherAvailabilityTest] added subject $key")
        return key
    }

    private fun tapId(id: String, described: String) {
        val element = device.wait(Until.findObject(By.res(id)), 15_000) ?: failWith(id, "$described never appeared")
        element.click()
    }

    private fun findScrolling(selector: androidx.test.uiautomator.BySelector): UiObject2? {
        var found = device.wait(Until.findObject(selector), 5_000)
        repeat(6) {
            if (found != null) return@repeat
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f)
            found = device.wait(Until.findObject(selector), 2_000)
        }
        return found
    }

    private fun list(array: JSONArray): List<String> = (0 until array.length()).map { array.getString(it) }

    private fun failWith(name: String, message: String): Nothing {
        capture("availability-$name")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
