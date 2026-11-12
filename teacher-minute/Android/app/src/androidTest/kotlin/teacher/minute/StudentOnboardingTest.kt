package teacher.minute

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The student app's guest start and sign-up on Android, against the local
 * Firebase emulators — the twin of the iOS StudentOnboardingUITests. QA test
 * plan:
 *
 *   AND-S-01  Start makes one anonymous user: users/{uid} role student,
 *             isAnonymous true, no minutes; home
 *   AND-S-02  a guest who asks is offered an account, and nothing is sent
 *   AND-S-03  a guest who signs up from that offer keeps the guest's uid,
 *             now an email/password account, isAnonymous false
 *   AND-S-09  a guest who logs in to an existing account is signed in to it,
 *             and the guest account and its profile are deleted
 *   AND-S-11  a guest signing up with an address in use is refused, with no
 *             second account, and stays the same guest
 *   AND-S-14  a guest who taps Buy minutes is offered an account instead
 *   AND-S-16  a teacher account is turned away with the other app's notice,
 *             signed out, its presence untouched
 *   AND-S-17  a guest's menu offers Log in; their profile offers an account
 *   AND-S-05  a guest's sign-up offers email and Google, no Apple
 *   AND-S-18  Back closes the offer; leaves sign-up for the intro (by design),
 *             the guest kept; and on home backgrounds the app, the guest kept
 *
 * AND-S-12, a guest killed and relaunched, is not here: the test runs in the
 * app's own process and cannot start it cold.
 *
 * It runs in the student flavor and skips itself in Pro Teacher:
 *
 *     ./gradlew :app:connectedStudentDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=teacher.minute.StudentOnboardingTest
 *
 * The tests find the app's guest by creation time: run them on their own, not
 * alongside another suite signing up on the same emulators.
 */
@RunWith(AndroidJUnit4::class)
class StudentOnboardingTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)

    private val dialogButton: BySelector = By.res("dialog_confirm_button")
    private val offer: BySelector = By.res("not_enough_minutes_primary")
    private val inUseMessages = listOf("This email address is already in use.", "כתובת המייל הזו כבר רשומה במערכת.")
    private val buyNeedsAccountMessages =
        listOf("Create an account or log in to buy minutes.", "צור חשבון או התחבר כדי לקנות דקות.")

    @Before
    fun setUp() {
        assumeTrue("the student app's test", context.packageName == "com.yaronj.student")
        assumeTrue("Firebase emulators not running", backend.isRunning())
        assumeTrue("needs a debug build on the emulators", AndroidFirebaseEmulator.host != null)

        FirebaseAuth.getInstance().signOut()
        val permissions = mutableListOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= 33) permissions += android.Manifest.permission.POST_NOTIFICATIONS
        for (permission in permissions) {
            instrumentation.uiAutomation.grantRuntimePermission(context.packageName, permission)
        }
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
    }

    /** AND-S-01: Start makes one anonymous student with no minutes. */
    @Test
    fun startingAsAGuestMakesOneAnonymousStudent() {
        val guest = startAsGuest()
        val profile = savedProfile(guest.uid)
        assertEquals("student", stringValue(profile, "role"))
        assertEquals(true, profile.optJSONObject("isAnonymous")?.optBoolean("booleanValue"))
        assertEquals("a guest has minutes", 0, intValue(profile, "remainingMinutes") ?: 0)
    }

    /** AND-S-02: a guest who asks is offered an account; nothing is sent. */
    @Test
    fun aGuestAskingIsOfferedAnAccount() {
        val guest = startAsGuest()
        askAndExpectTheOffer()
        assertEquals("a guest's question was created", 0, backend.count("questions", "studentUid", guest.uid))
    }

    /** AND-S-03: signing up from the offer keeps the guest's uid. */
    @Test
    fun aGuestSigningUpKeepsTheirUid() {
        val guest = startAsGuest()
        askAndExpectTheOffer()
        device.findObject(offer).click()
        val email = backend.newEmail("guest.signup")
        val password = "Emulator-${(100_000..999_999).random()}"
        assertTrue("Create account did not open sign-up", device.wait(Until.hasObject(By.res("sign_up_email")), 20_000))
        fillSignUp(email, password)
        submitSignUp()
        finishOnboarding("Guest Turned Student")

        val users = backend.users(email)
        assertEquals("the account is not the guest's uid", listOf(guest.uid), users.map { it.first })
        assertEquals(listOf("password"), users.first().second)
        val profile = savedProfile(guest.uid)
        assertEquals("the profile still says anonymous", false, profile.optJSONObject("isAnonymous")?.optBoolean("booleanValue"))
        assertEquals("student", stringValue(profile, "role"))
        assertTrue("signing up left another anonymous user", anonymousUsers(guest.createdAt).isEmpty())
    }

    /** AND-S-09: logging in to an existing account deletes the guest. */
    @Test
    fun aGuestLoggingInDropsTheGuestAccount() {
        val existing = backend.createAccount("guest.login")
        backend.merge("users/${existing.uid}", mapOf("role" to "student", "fullName" to "Existing Student"))
        val guest = startAsGuest()

        logInFromTheMenu(existing.email, existing.password)
        if (!waitForHome(90_000)) failWithScreen("login", "logging in did not reach home")

        var gone = false
        repeat(30) {
            if (!gone && backend.user(guest.uid) == null) gone = true
            if (!gone) Thread.sleep(1_000)
        }
        assertTrue("the guest account is still in Auth", gone)
        assertNull("the guest's profile is still there", backend.strings("users/${guest.uid}"))
        assertNotNull("the existing account is gone", backend.user(existing.uid))
        assertEquals("not signed in to the existing account", existing.uid, FirebaseAuth.getInstance().currentUser?.uid)
    }

    /** AND-S-11: a guest signing up with a taken address is refused. */
    @Test
    fun aGuestSigningUpWithATakenAddressIsRefused() {
        val existing = backend.createAccount("guest.taken")
        val guest = startAsGuest()
        askAndExpectTheOffer()
        device.findObject(offer).click()
        assertTrue("Create account did not open sign-up", device.wait(Until.hasObject(By.res("sign_up_email")), 20_000))
        fillSignUp(existing.email, "Emulator-123456")
        submitSignUp()

        val ok = device.wait(Until.findObject(dialogButton), 30_000) ?: failWithScreen("taken", "a taken address showed no error")
        val screen = screenText()
        assertTrue("the error does not say the address is in use: $screen", inUseMessages.any { screen.contains(it) })
        ok.click()
        assertEquals("the address has more than one account", 1, backend.users(existing.email).size)
        assertEquals("the guest is no longer an anonymous account", true, backend.user(guest.uid)?.isAnonymous)
    }

    /** AND-S-14: a guest who taps Buy minutes is offered an account. */
    @Test
    fun aGuestBuyingMinutesIsOfferedAnAccount() {
        startAsGuest()
        openTextTab()
        val buy = findScrolling(By.res("load_minutes")) ?: failWithScreen("buy", "no Buy minutes on a guest's home")
        buy.click()
        if (!device.wait(Until.hasObject(offer), 15_000)) failWithScreen("buy-offer", "Buy minutes did not offer an account")
        val screen = screenText()
        assertTrue(
            "the offer does not say an account is needed to buy: $screen",
            buyNeedsAccountMessages.any { screen.contains(it) }
        )
    }

    /** AND-S-16: a teacher account is turned away, signed out, its presence
     *  untouched. */
    @Test
    fun aTeacherAccountIsTurnedAway() {
        val teacher = backend.createAccount("student-app.teacher")
        backend.merge(
            "users/${teacher.uid}",
            mapOf("role" to "teacher", "fullName" to "Wrong App Teacher", "phoneNumber" to "0521234567")
        )
        backend.put("teachers/${teacher.uid}", JSONObject().put("status", "offline"))
        startAsGuest()

        logInFromTheMenu(teacher.email, teacher.password)
        val ok = device.wait(Until.findObject(dialogButton), 60_000) ?: failWithScreen("teacher", "a teacher account got no notice")
        println("[StudentOnboardingTest] notice: ${screenText()}")
        ok.click()
        assertEquals("teacher", backend.strings("users/${teacher.uid}")?.get("role"))
        assertEquals("the student app changed the teacher's presence", "offline", backend.value("teachers/${teacher.uid}/status"))
        assertFalse("the teacher is listed online", backend.exists("onlineTeachers/${teacher.uid}"))
        assertTrue(
            "the teacher account stayed signed in",
            FirebaseAuth.getInstance().currentUser?.uid != teacher.uid
        )
    }

    /** AND-S-17: a guest's menu offers Log in, and their profile says they
     *  have no account and offers one, with no empty name to fill. */
    @Test
    fun aGuestsMenuAndProfileOfferAnAccount() {
        startAsGuest()
        openSideMenu()
        assertTrue("a guest's menu has no Log in", device.wait(Until.hasObject(By.res("side_menu_log_in")), 15_000))
        (device.wait(Until.findObject(By.res("side_menu_item_profile")), 10_000)
            ?: failWithScreen("menu-profile", "no Profile in a guest's menu")).click()
        val create = findScrolling(By.res("profile_create_account_button"))
            ?: failWithScreen("guest-profile", "a guest's profile offers no account")
        assertFalse("a guest's profile has a field to fill", device.hasObject(By.clazz("android.widget.EditText")))
        create.click()
        if (!device.wait(Until.hasObject(By.res("sign_up_email")), 20_000)) failWithScreen("guest-sign-up", "Create account did not open sign-up")
    }

    /** AND-S-05: a guest's sign-up offers email and Google, and no Apple. */
    @Test
    fun aGuestsSignUpOffersEmailAndGoogleOnly() {
        startAsGuest()
        askAndExpectTheOffer()
        device.findObject(offer).click()
        if (!device.wait(Until.hasObject(By.res("sign_up_email")), 20_000)) failWithScreen("sign-up", "Create account did not open sign-up")
        assertNotNull("sign-up offers no Google", findScrolling(By.res("sign_up_google")))
        assertFalse("sign-up offers Apple on Android", device.hasObject(By.res("sign_up_apple")))
    }

    /** AND-S-18: Back closes the offer, leaves sign-up for the screen before
     *  it, and on home sends the app to the background with the guest kept. */
    @Test
    fun backAsAGuestStepsBackAndKeepsTheGuest() {
        val guest = startAsGuest()
        askAndExpectTheOffer()
        device.pressBack()
        assertTrue("Back did not close the offer", device.wait(Until.gone(offer), 10_000))
        if (!device.wait(Until.hasObject(By.res("question_home_mode_text")), 5_000)) {
            failWithScreen("back-offer", "Back on the offer left home; foreground is ${device.currentPackageName}")
        }

        askAgainForTheOffer()
        device.findObject(offer).click()
        if (!device.wait(Until.hasObject(By.res("sign_up_email")), 20_000)) failWithScreen("back-sign-up", "Create account did not open sign-up")
        device.pressBack()
        // A Back that only closed the keyboard leaves the form up: press again.
        if (!device.wait(Until.gone(By.res("sign_up_email")), 3_000)) device.pressBack()
        assertTrue("Back did not leave sign-up", device.wait(Until.gone(By.res("sign_up_email")), 10_000))
        // By design (AppRouter.startRegistration) sign-up sits on the welcome
        // stack: backing out lands on the intro, still signed in as the guest,
        // and Get started returns that same guest home.
        val intro = device.wait(Until.findObject(By.res("student_intro_start")), 20_000)
            ?: failWithScreen("back-sign-up", "Back from sign-up did not reach the intro; foreground is ${device.currentPackageName}")
        assertEquals("backing out of sign-up signed the guest out", guest.uid, FirebaseAuth.getInstance().currentUser?.uid)
        intro.click()
        val introDeadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < introDeadline && !device.wait(Until.gone(By.res("student_intro_start")), 3_000)) {
            runCatching { device.findObject(By.res("student_intro_start"))?.click() }
        }
        if (!waitForHome(30_000)) failWithScreen("back-start", "Get started after backing out did not return home")
        assertEquals("Get started made a new guest", guest.uid, FirebaseAuth.getInstance().currentUser?.uid)

        device.pressBack()
        assertTrue("Back on home did not send the app to the background",
            device.wait(Until.gone(By.pkg(context.packageName).depth(0)), 10_000))
        context.startActivity(
            context.packageManager.getLaunchIntentForPackage(context.packageName)!!.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        assertTrue("reopening did not return home", waitForHome(60_000))
        assertEquals("reopening is not the same guest", guest.uid, FirebaseAuth.getInstance().currentUser?.uid)
        assertTrue("the guest became someone else", backend.user(guest.uid)?.isAnonymous == true)
    }

    /** The offer again, after Back closed it: the question is still written. */
    private fun askAgainForTheOffer() {
        repeat(6) {
            if (device.hasObject(offer)) return
            findScrolling(By.res("find_teacher"))?.click()
            device.wait(Until.hasObject(offer), 15_000)
            if (!device.hasObject(offer)) device.findObject(dialogButton)?.let { it.click(); Thread.sleep(3_000) }
        }
        if (!device.hasObject(offer)) failWithScreen("offer-again", "asking again did not offer an account")
    }

    /** X-05 / X-06, the Android half: the account made on the iPhone
     *  (StudentOnboardingUITests.testCrossPlatformSignUpOnTheIPhone) logged
     *  into from an Android guest. Same uid, the iPhone's name and minutes
     *  untouched, the Android guest deleted, no extra account. Skipped unless
     *  the run passes `-e crossEmail … -e crossPassword …`. */
    @Test
    fun crossPlatformLogInFindsTheSameAccount() {
        val args = InstrumentationRegistry.getArguments()
        val email = args.getString("crossEmail")
        val password = args.getString("crossPassword")
        assumeTrue("pass crossEmail and crossPassword to run the cross-platform log-in", email != null && password != null)
        val account = backend.users(email!!).singleOrNull()
            ?: failWithScreen("cross", "no single account for $email: was the iPhone half run?")
        val guest = startAsGuest()

        logInFromTheMenu(email, password!!)
        if (!waitForHome(90_000)) failWithScreen("cross-login", "logging in with the iPhone's account did not reach home")

        assertEquals("not signed in to the iPhone's account", account.first, FirebaseAuth.getInstance().currentUser?.uid)
        val profile = backend.fields("users/${account.first}") ?: JSONObject()
        assertEquals("Cross Platform Student", stringValue(profile, "fullName"))
        assertEquals("the minutes changed on logging in from Android", 37, intValue(profile, "remainingMinutes"))
        var gone = false
        repeat(30) {
            if (!gone && backend.user(guest.uid) == null) gone = true
            if (!gone) Thread.sleep(1_000)
        }
        assertTrue("the Android guest is still in Auth", gone)
        assertEquals("the address has more than one account", 1, backend.users(email).size)
    }

    // Steps

    /** Taps Start on the intro; returns the one anonymous user made since. */
    private fun startAsGuest(): EmulatorBackend.AuthUser {
        val before = System.currentTimeMillis() - 2_000
        val start = device.wait(Until.findObject(By.res("student_intro_start")), 60_000)
            ?: failWithScreen("intro", "the intro's Start never appeared")
        start.click()
        // Right after a relaunch the old intro can swallow the first tap.
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && !device.wait(Until.gone(By.res("student_intro_start")), 3_000)) {
            runCatching { device.findObject(By.res("student_intro_start"))?.click() }
        }
        if (!waitForHome(60_000)) failWithScreen("home", "Start did not reach home")
        var guests = emptyList<EmulatorBackend.AuthUser>()
        repeat(20) {
            if (guests.isEmpty()) {
                guests = anonymousUsers(before)
                if (guests.isEmpty()) Thread.sleep(500)
            }
        }
        assertEquals("Start made ${guests.size} anonymous users", 1, guests.size)
        return guests.first()
    }

    /** The profile once it holds a role: the app saves it without waiting for
     *  the write to land, so a read straight after Start can find nothing. */
    private fun savedProfile(uid: String): JSONObject {
        var profile = JSONObject()
        repeat(30) {
            profile = backend.fields("users/$uid") ?: JSONObject()
            if (stringValue(profile, "role") != null) return profile
            Thread.sleep(500)
        }
        return profile
    }

    private fun anonymousUsers(since: Long) = backend.allUsers().filter { it.isAnonymous && it.createdAt >= since }

    /** Home, past the tutorial a new student is shown first. */
    private fun waitForHome(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res("student_tutorial_skip"))?.let { runCatching { it.click() } }
            device.findObject(By.res("permissions_setup_skip"))?.let { runCatching { it.click() } }
            if (device.hasObject(By.res("question_home_mode_text")) && !device.hasObject(By.res("student_tutorial_skip")) &&
                !device.hasObject(By.res("email_input"))
            ) return true
            Thread.sleep(1_000)
        }
        return false
    }

    /** Writes a question and taps Find a teacher; a guest must get the offer. */
    private fun askAndExpectTheOffer() {
        openTextTab()
        type("Guest question: what is 2 + 2?", into = "question_text")
        device.pressBack() // the keyboard
        repeat(6) {
            if (device.hasObject(offer)) return@repeat
            findScrolling(By.res("find_teacher"))?.click()
            device.wait(Until.hasObject(offer), 20_000)
            // "Checking your balance" first, while the profile loads.
            if (!device.hasObject(offer)) device.findObject(dialogButton)?.let { it.click(); Thread.sleep(3_000) }
        }
        if (!device.hasObject(offer)) failWithScreen("offer", "a guest asking was not offered an account")
        assertFalse("a guest's question went out", device.hasObject(By.res("search_details_cancel")))
    }

    /** Home opens on the photo tab; the question field, Find a teacher and
     *  Buy minutes are on the text tab. */
    private fun openTextTab() {
        val tab = device.wait(Until.findObject(By.res("question_home_mode_text")), 20_000)
            ?: failWithScreen("text-tab", "no Text tab at home")
        tab.click()
        if (!device.wait(Until.hasObject(By.res("question_text")), 10_000)) failWithScreen("text-tab", "the Text tab did not open")
    }

    private fun logInFromTheMenu(email: String, password: String) {
        openSideMenu()
        val logIn = device.wait(Until.findObject(By.res("side_menu_log_in")), 15_000)
            ?: failWithScreen("menu", "no Log in in a guest's menu")
        logIn.click()
        if (!device.wait(Until.hasObject(By.res("email_input")), 20_000)) failWithScreen("login", "the login form did not open")
        type(email, into = "email_input")
        type(password, into = "password_input")
        device.findObject(By.res("login_submit")).click()
    }

    private fun openSideMenu() {
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res("side_menu_button"))?.let { it.click(); return }
            device.findObject(By.res("student_tutorial_skip"))?.click()
            Thread.sleep(1_000)
        }
        failWithScreen("side-menu", "the side-menu button never appeared")
    }

    private fun fillSignUp(email: String, password: String) {
        type(email, into = "sign_up_email")
        type(password, into = "sign_up_password")
        type(password, into = "sign_up_confirm_password")
        (findScrolling(By.res("sign_up_terms")) ?: failWithScreen("terms", "no terms box")).click()
    }

    private fun submitSignUp() {
        (findScrolling(By.res("sign_up_continue")) ?: failWithScreen("sign-up", "no sign-up Continue")).click()
    }

    /** Walks whichever steps follow sign-up — profile, email verification,
     *  permissions — to home. */
    private fun finishOnboarding(name: String) {
        var filledName = false
        val deadline = System.currentTimeMillis() + 150_000
        while (System.currentTimeMillis() < deadline) {
            if (waitForHome(1_000)) return
            if (!filledName && device.hasObject(By.res("complete_profile_full_name"))) {
                type(name, into = "complete_profile_full_name")
                filledName = true
            }
            if (filledName) {
                device.findObject(By.res("complete_profile_continue"))?.takeIf { it.isEnabled }?.let { runCatching { it.click() } }
            }
            device.findObject(By.res("verify_email_not_now"))?.let { runCatching { it.click() } }
        }
        failWithScreen("onboarding", "sign-up did not reach home")
    }

    /** SkipUI tags a container; the EditText inside it takes the text. */
    private fun type(text: String, into: String) {
        val tagged = device.wait(Until.findObject(By.res(into)), 20_000) ?: failWithScreen(into, "no $into")
        val field = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    private fun findScrolling(selector: BySelector): UiObject2? {
        var found = device.wait(Until.findObject(selector), 5_000)
        repeat(6) {
            if (found != null) return@repeat
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f)
            found = device.wait(Until.findObject(selector), 2_000)
        }
        return found
    }

    private fun screenText(): String =
        device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }
            .filter { it.isNotBlank() }.joinToString(" | ")

    private fun stringValue(fields: JSONObject, key: String): String? =
        fields.optJSONObject(key)?.optString("stringValue")?.takeIf { it.isNotEmpty() }

    private fun intValue(fields: JSONObject, key: String): Int? =
        fields.optJSONObject(key)?.optString("integerValue")?.toIntOrNull()

    /** Saves a screenshot and the hierarchy to files/ui-test, then fails. */
    private fun failWithScreen(name: String, message: String): Nothing {
        val dir = java.io.File(context.filesDir, "ui-test").apply { mkdirs() }
        device.takeScreenshot(java.io.File(dir, "onboarding-$name.png"))
        java.io.File(dir, "onboarding-$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        fail("$message: ${screenText()}")
        throw AssertionError(message)
    }
}
