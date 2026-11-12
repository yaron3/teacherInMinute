package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Date

/**
 * Settings a teacher uses, against the local Firebase emulators — the Android
 * twin of the iOS ProTeacherSettingsUITests. QA test plan:
 *
 *   AND-G-01  Settings → Language → Hebrew: the tab bar runs right to left;
 *             → English: left to right again. The copy follows Remote Config,
 *             which the emulators cannot serve, so it stays a manual check
 *   AND-G-05  a message in the inbox shows in Messages, and opening it marks
 *             it read (readTimestamp)
 *   AND-G-10  About → Terms and About → Privacy Policy each open the page in
 *             the browser
 *   AND-G-06  editing the profile saves a new name and phone, and shows them
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherSettingsTest : ProTeacherEmulatorTest() {

    override val signsInAtStart = false

    /** AND-G-05: an unread message is listed, then marked read. */
    @Test
    fun anInboxMessageIsShownAndMarkedRead() {
        val title = "Emulator notice ${(1000..9999).random()}"
        backend.merge(
            "users/${appTeacher.uid}/incomingMessages/emulator-notice",
            mapOf("title" to title, "text" to "Your documents were approved.", "createdAt" to Date())
        )
        signIn()

        tapId("messages_button", "Messages")
        if (!device.wait(Until.hasObject(By.text(title)), 20_000)) failWith("inbox", "the message is not in Messages")

        var read = false
        val deadline = System.currentTimeMillis() + 20_000
        while (!read && System.currentTimeMillis() < deadline) {
            read = backend.fields("users/${appTeacher.uid}/incomingMessages/emulator-notice")?.has("readTimestamp") == true
            if (!read) Thread.sleep(500)
        }
        assertTrue("opening Messages did not mark the message read", read)
    }

    /** AND-G-01: Hebrew and back, the tab bar flipping each way. */
    @Test
    fun switchingLanguageFlipsTheAppAndBack() {
        signIn()
        openSettingsRow("language")

        // The tab bar is hidden on the Language page: checked back on Settings.
        // A tap while the page is still settling after the previous switch's
        // reload can miss, so each switch is tried up to three times.
        switchLanguage(hebrew = true, alreadyOpen = true)
        switchLanguage(hebrew = false, alreadyOpen = false)
    }

    /** AND-G-10: Terms and Privacy Policy each open in the browser. */
    @Test
    fun aboutOpensTheTermsAndPrivacyPages() {
        signIn()
        openSettingsRow("about")

        for (row in listOf("eula", "privacyPolicy")) {
            tapId("settings_row_$row", row)
            tapId("about_open_link", "the page's open button")
            val left = device.wait(Until.gone(By.pkg(context.packageName).depth(0)), 15_000)
            if (!left) failWith("browser-$row", "$row did not open the browser")
            println("[ProTeacherSettingsTest] $row opened ${device.currentPackageName}")
            device.pressBack()
            if (!device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 15_000)) {
                failWith("back-$row", "Back from the browser did not return to the app")
            }
            tapId("brand_back_button", "Back")
        }
    }

    /** AND-G-06: a new name and phone are saved to the profile and shown. */
    @Test
    fun editingTheProfileSavesNameAndPhone() {
        signIn()
        tapId("tab_item_profile", "the Profile tab")
        tapId("profile_edit_button", "Edit profile")
        val name = "Renamed Teacher ${(100..999).random()}"
        typeInto("profile_field_name", name)
        typeInto("profile_field_phone", "0529876543")
        val save = findScrolling(By.res("profile_save_button")) ?: failWith("save", "no Save in the profile editor")
        save.click()
        if (!device.wait(Until.gone(By.res("profile_save_button")), 20_000)) failWith("save", "saving did not close the editor")

        var saved = emptyMap<String, String>()
        val deadline = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < deadline && saved["fullName"] != name) {
            saved = backend.strings("users/${appTeacher.uid}") ?: emptyMap()
            if (saved["fullName"] != name) Thread.sleep(500)
        }
        assertTrue("the new name was not saved: $saved", saved["fullName"] == name)
        assertTrue("the new phone was not saved: $saved", saved["phoneNumber"] == "0529876543")
        assertTrue("the profile does not show the new name", device.wait(Until.hasObject(By.text(name)), 10_000))
    }

    private fun typeInto(id: String, text: String) {
        val tagged = findScrolling(By.res(id)) ?: failWith(id, "no $id in the profile editor")
        val field = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    // Steps

    private fun openSettingsRow(id: String) {
        tapId("tab_item_settings", "the Settings tab")
        repeat(3) {
            val row = runCatching { findScrolling(By.res("settings_row_$id")) }.getOrNull()
            if (row != null && runCatching { row.click() }.isSuccess) return
            Thread.sleep(1_000) // redrawn under the tap; find it again
        }
        failWith("settings", "no $id row in Settings")
    }

    private fun switchLanguage(hebrew: Boolean, alreadyOpen: Boolean) {
        val row = if (hebrew) "language_row_hebrew" else "language_row_english"
        for (attempt in 1..3) {
            if (attempt > 1 || !alreadyOpen) openSettingsRow("language")
            Thread.sleep(1_500)
            tapId(row, row)
            leaveLanguagePage()
            if (layoutFlipped(hebrew, timeoutMs = 10_000)) return
        }
        expectLanguage(hebrew)
    }

    private fun layoutFlipped(hebrew: Boolean, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val home = runCatching { device.findObject(By.res("tab_item_home"))?.visibleBounds }.getOrNull()
            val settings = runCatching { device.findObject(By.res("tab_item_settings"))?.visibleBounds }.getOrNull()
            if (home != null && settings != null && (if (hebrew) home.left > settings.left else home.left < settings.left)) return true
            Thread.sleep(500)
        }
        return false
    }

    /** Back to where the tab bar shows. Picking a language reloads the app at
     *  home, so there may be no Back to tap. */
    private fun leaveLanguagePage() {
        Thread.sleep(2_000)
        runCatching { device.findObject(By.res("brand_back_button"))?.click() }
    }

    /** The Settings tab's label in the chosen language, and the tab bar's
     *  order: Home first on the left in English, on the right in Hebrew. */
    private fun expectLanguage(hebrew: Boolean) {
        val title = if (hebrew) "הגדרות" else "Settings"
        var labelled = false
        var flipped = false
        val deadline = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < deadline) {
            labelled = runCatching { device.hasObject(By.text(title)) }.getOrDefault(false)
            // The app redraws itself in the new language: a tab found a moment
            // ago can be gone by the time its bounds are read.
            val home = runCatching { device.findObject(By.res("tab_item_home"))?.visibleBounds }.getOrNull()
            val settings = runCatching { device.findObject(By.res("tab_item_settings"))?.visibleBounds }.getOrNull()
            flipped = home != null && settings != null &&
                if (hebrew) home.left > settings.left else home.left < settings.left
            if (!flipped) Thread.sleep(500)
            if (flipped) break
        }
        // The words come from Remote Config, which the emulators cannot serve:
        // the app keeps the template it last fetched, so only the layout is
        // checked and the copy stays a manual check.
        println("[ProTeacherSettingsTest] ${if (hebrew) "Hebrew" else "English"}: labels match=$labelled")
        if (!flipped) {
            failWith("language", "${if (hebrew) "Hebrew" else "English"}: labelled=$labelled right-to-left order=$flipped")
        }
    }

    private fun tapId(id: String, described: String) {
        repeat(3) {
            val element = device.wait(Until.findObject(By.res(id)), 15_000) ?: failWith(id, "$described never appeared")
            if (runCatching { element.click() }.isSuccess) return
            Thread.sleep(1_000) // redrawn under the tap; find it again
        }
        failWith(id, "$described kept being redrawn under the tap")
    }

    private fun findScrolling(selector: androidx.test.uiautomator.BySelector): UiObject2? {
        var found = device.wait(Until.findObject(selector), 5_000)
        repeat(6) {
            if (found != null) return@repeat
            runCatching { device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f) }
            found = device.wait(Until.findObject(selector), 2_000)
        }
        return found
    }

    private fun failWith(name: String, message: String): Nothing {
        capture("settings-$name")
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
