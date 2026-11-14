package teacher.minute

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.google.firebase.auth.FirebaseAuth
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.util.regex.Pattern

/**
 * Pro Teacher's sign-up and onboarding on Android, against the real backend on
 * the local Firebase emulators — the twin of the iOS ProTeacherSignUpUITests.
 * QA test plan:
 *
 *   AND-T-01  email sign-up through every onboarding step reaches the
 *             dashboard: one new Auth user (password), users/{uid}.role
 *             teacher, with the name and phone typed
 *   AND-T-05  with teacher_identity_onboarding off — its default, and the
 *             emulators have no Remote Config — sign-up goes straight to the
 *             profile, with no ID step
 *   AND-T-06  subjects: none cannot continue; two are saved
 *   AND-T-07  the profile cannot be finished without a name and a valid phone
 *   AND-T-11  an address already in use is refused, with no second user
 *   AND-T-12  a bad address, a short password, a mismatched confirmation or
 *             unaccepted terms are each refused, and nothing is created
 *   AND-T-13  a student account is turned away with the other app's notice,
 *             signed out, its role untouched
 *
 * AND-T-10, resuming after the app is killed, is not here: the test runs in
 * the app's own process, so it cannot kill the app and start it cold.
 *
 * Each test starts on the login form. Run like ProTeacherAcceptRaceTest.
 */
@RunWith(AndroidJUnit4::class)
class ProTeacherSignUpTest : ProTeacherEmulatorTest() {

    override val signsInAtStart = false

    private val dialogButton: BySelector = By.res("dialog_confirm_button")
    private var termsChecked = false
    /** "This email address is already in use.", in either language. */
    private val inUseMessages = listOf("This email address is already in use.", "כתובת המייל הזו כבר רשומה במערכת.")

    /** AND-T-01 and AND-T-05: an email sign-up, through the profile, to the
     *  dashboard. */
    @Test
    fun emailSignUpReachesTheDashboard() {
        val email = backend.newEmail("signup.teacher")
        val password = "Emulator-${(100_000..999_999).random()}"
        openSignUpForm()
        fillSignUp(email, password, password, agreeToTerms = true)
        submitSignUp()

        // T-05: the profile comes next, not the ID step.
        reachProfile()
        assertFalse("sign-up showed the subjects step", device.hasObject(By.res("teacher_subjects_continue")))
        type("Signup Teacher", into = "complete_profile_full_name")
        type("0521234567", into = "complete_profile_phone")
        findScrolling(By.res("complete_profile_continue"))!!.click()
        // No payout method picked: the app asks, and the test continues anyway.
        val continueAnyway = device.wait(Until.findObject(dialogButton), 15_000)
        assertNotNull("the missing-payout question did not appear", continueAnyway)
        continueAnyway.click()
        reachDashboard("finishing the profile")
        // Kept for a look at the dashboard and its tab bar (Bug-014).
        capture("dashboard")

        val users = backend.users(email)
        assertEquals("signing up made ${users.size} Auth users", 1, users.size)
        val (uid, providers) = users.first()
        assertEquals(listOf("password"), providers)
        val profile = backend.strings("users/$uid") ?: emptyMap()
        assertEquals("teacher", profile["role"])
        assertEquals("Signup Teacher", profile["fullName"])
        assertEquals("0521234567", profile["phoneNumber"])
    }

    /** AND-T-04: with the ID step on (the debug Remote Config override
     *  `rcOverride.teacher_identity_onboarding`), sign-up leads to it; the
     *  front alone, picked from the gallery, uploads as `govId_<uid>_front` and
     *  lets the teacher go on to the subjects. The photo is a full-size 50 MP
     *  picture (8160 × 6144) — what the testers' phone takes — which the run
     *  pushes to /sdcard/Pictures/id-50mp.jpg; skipped without it. */
    @Test
    fun theIDStepTakesTheFrontAlone() {
        val photo = "id-50mp"
        val prefs = context.getSharedPreferences("defaults", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("rcOverride.teacher_identity_onboarding", true).commit()
        try {
            val email = backend.newEmail("signup.identity")
            val password = "Emulator-${(100_000..999_999).random()}"
            openSignUpForm()
            fillSignUp(email, password, password, agreeToTerms = true)
            submitSignUp()

            val front = device.wait(Until.findObject(By.res("identity_front_upload")), 60_000)
            if (front == null) {
                capture("identity-step")
                fail("signing up did not reach the ID step: ${screenText()}")
            }
            assertFalse("the profile came before the ID step", device.hasObject(By.res("complete_profile_full_name")))
            front!!.click()
            val library = device.wait(Until.findObject(By.text(Pattern.compile("Choose from Library|בחר מהספרייה"))), 15_000)
            assertNotNull("the ID front offered no gallery", library)
            library!!.click()

            // The system's document picker: the photo by its name, which a
            // grid tile carries in its description and a list row as text.
            val byName = { device.findObject(By.descStartsWith(photo)) ?: device.findObject(By.textContains(photo)) }
            var picked: UiObject2? = null
            val pickerDeadline = System.currentTimeMillis() + 20_000
            while (picked == null && System.currentTimeMillis() < pickerDeadline) {
                picked = byName()
                if (picked == null) Thread.sleep(500)
            }
            if (picked == null) {
                capture("identity-picker")
                fail("the picker did not show $photo: ${screenText()}")
            }
            picked!!.click()

            // Back in the app, the upload lands on the user.
            val back = device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
            assertTrue("the app did not come back from the picker (crashed?)", back)
            var uid = ""
            var documents = emptyList<String>()
            val deadline = System.currentTimeMillis() + 120_000
            while (System.currentTimeMillis() < deadline) {
                if (uid.isEmpty()) uid = backend.users(email).firstOrNull()?.first ?: ""
                if (uid.isNotEmpty()) {
                    documents = backend.stringArray("users/$uid", "uploadedDocuments")
                    if (documents.contains("govId_${uid}_front")) break
                }
                if (!device.hasObject(By.pkg(context.packageName).depth(0))) {
                    capture("identity-gone")
                    fail("the app left the screen while uploading (crashed?)")
                }
                Thread.sleep(1_000)
            }
            println("[ProTeacherSignUpTest] ID step: ${screenText()}")
            assertEquals("the uploaded documents are $documents", listOf("govId_${uid}_front"), documents)

            // Front only: with the declaration ticked, Submit leads on.
            findScrolling(By.res("identity_terms"))?.click()
            // Found afresh: ticking redraws the step.
            assertNotNull("no Submit for review", findScrolling(By.res("identity_submit")))
            assertTrue("the front alone does not let the teacher go on",
                device.wait(Until.hasObject(By.res("identity_submit").enabled(true)), 10_000))
            device.findObject(By.res("identity_submit")).click()
            assertTrue("the ID step did not lead on to the subjects",
                device.wait(Until.hasObject(By.res("teacher_subjects_continue")), 30_000))
        } finally {
            prefs.edit().remove("rcOverride.teacher_identity_onboarding").commit()
        }
    }

    /** The testers' YouTrack fixes along one sign-up:
     *  - IT-5 / IT-2: the password field's eye shows what was typed;
     *  - IT-7: the profile marks its required fields with an asterisk;
     *  - IT-9: a US number, in the international form the placeholder shows,
     *    is a valid profile phone;
     *  - IT-6: Profile's "Complete your documents" opens full screen, not as
     *    a bottom sheet leaving Profile showing above it;
     *  - IT-8: searching the subjects for a subtopic lists that subtopic,
     *    and a search matching nothing says so. */
    @Test
    fun theTestersSignUpAndProfileFixes() {
        val email = backend.newEmail("signup.fixes")
        val password = "Emulator-${(100_000..999_999).random()}"
        openSignUpForm()

        // IT-5: the eye shows the password as typed.
        type(password, into = "sign_up_password")
        val eye = findScrolling(By.res("password_visibility_toggle"))
        assertNotNull("the password field has no eye", eye)
        eye!!.click()
        val shown = device.wait(Until.findObject(By.clazz("android.widget.EditText").hasAncestor(By.res("sign_up_password")).text(password)), 5_000)
        assertNotNull("the eye did not show the password", shown)
        fillSignUp(email, password, password, agreeToTerms = true)
        submitSignUp()
        reachProfile()

        // IT-7: the required fields say so.
        val starred = device.findObjects(By.text(Pattern.compile(".+ \\*")))
        println("[ProTeacherSignUpTest] required titles: ${starred.map { it.text }}")
        assertTrue("the profile marks ${starred.size} fields required, not the name and the phone", starred.size >= 2)

        // IT-9: a US number in international form.
        type("Fixes Teacher", into = "complete_profile_full_name")
        type("+1 (555) 123-4567", into = "complete_profile_phone")
        assertTrue("Continue stayed off with a US number", profileContinueEnabled())
        findScrolling(By.res("complete_profile_continue"))!!.click()
        device.wait(Until.findObject(dialogButton), 15_000)?.click()
        reachDashboard("finishing the profile")
        val uid = backend.users(email).first().first
        assertEquals("+15551234567", backend.strings("users/$uid")?.get("phoneNumber"))

        // IT-6: the documents page covers Profile.
        // A tap while the dashboard is still settling can be lost: tap again.
        var documents: UiObject2? = null
        repeat(3) {
            if (documents != null) return@repeat
            device.wait(Until.findObject(By.res("tab_item_profile")), 15_000)?.click()
            // Profile shows the documents only once it has loaded a teacher.
            documents = device.wait(Until.findObject(By.res("profile_documents_button")), 20_000)
                ?: findScrolling(By.res("profile_documents_button"))
        }
        if (documents == null) {
            capture("profile-tab")
            fail("Profile shows no documents button: ${screenText()}")
        }
        documents!!.click()
        val close = device.wait(Until.findObject(By.res("brand_sheet_close")), 15_000)
        assertNotNull("Complete your documents did not open", close)
        capture("documents-open")
        assertTrue("the documents page starts ${close!!.visibleBounds.top}px down, below Profile",
            close.visibleBounds.top < device.displayHeight * 0.15)
        close.click()
        assertTrue("the documents page did not close", device.wait(Until.gone(By.res("brand_sheet_close")), 10_000))

        // IT-8: a subtopic found by search is listed; nothing found is said.
        findScrolling(By.res("profile_subjects_edit_button"))!!.click()
        val search = device.wait(Until.findObject(By.clazz("android.widget.EditText").hasAncestor(By.res("teacher_subjects_search"))), 15_000)
            ?: device.wait(Until.findObject(By.res("teacher_subjects_search")), 5_000)
        assertNotNull("the subjects editor has no search", search)
        search!!.click()
        search.text = "Geometry"
        assertNotNull("searching for Geometry did not list it",
            device.wait(Until.findObject(By.res(Pattern.compile("subject_chip_(?i)geometry"))), 10_000))
        search.text = "zzzz"
        assertNotNull("a search matching nothing said nothing",
            device.wait(Until.findObject(By.res("teacher_subjects_no_results")), 10_000))
    }

    /** AND-T-07: the profile's Continue stays off until there is a name and a
     *  valid phone, which a teacher must give. */
    @Test
    fun profileNeedsANameAndAValidPhone() {
        val password = "Emulator-${(100_000..999_999).random()}"
        openSignUpForm()
        fillSignUp(backend.newEmail("signup.profile"), password, password, agreeToTerms = true)
        submitSignUp()
        reachProfile()

        assertFalse("Continue was on with nothing filled in", profileContinueEnabled())
        type("Profile Teacher", into = "complete_profile_full_name")
        assertFalse("Continue was on without a phone", profileContinueEnabled())
        type("123", into = "complete_profile_phone")
        assertFalse("Continue was on with the phone 123", profileContinueEnabled())
        type("0521234567", into = "complete_profile_phone")
        assertTrue("Continue stayed off with a name and a valid phone", profileContinueEnabled())
        type("", into = "complete_profile_full_name")
        assertFalse("Continue was on without a name", profileContinueEnabled())
    }

    /** AND-T-06: subjects. A teacher with a profile but no subjects is sent to
     *  them; Continue needs a subject, and the ones picked are saved. */
    @Test
    fun subjectsAreRequiredAndSaved() {
        val teacher = backend.createAccount("signup.subjects")
        backend.merge(
            "users/${teacher.uid}",
            mapOf("role" to "teacher", "fullName" to "Subjects Teacher", "phoneNumber" to "0521234567")
        )
        submitLogin(teacher.email, teacher.password)

        val continueSelector = By.res("teacher_subjects_continue")
        if (!device.wait(Until.hasObject(continueSelector), 60_000)) {
            capture("subjects")
            fail("a teacher without subjects was not sent to them: ${screenText()}")
        }
        assertFalse("Continue was on with no subject", findScrolling(continueSelector)!!.isEnabled)

        val area = findScrolling(By.res(Pattern.compile("teacher_subject_area_.*")), Direction.UP)
        assertNotNull("no subject area to pick", area)
        area!!.click()
        val chips = By.res(Pattern.compile("subject_chip_.*"))
        assertTrue("picking an area showed no subjects", device.wait(Until.hasObject(chips), 10_000))
        val picked = mutableSetOf<String>()
        repeat(6) {
            if (picked.size >= 2) return@repeat
            for (chip in device.findObjects(chips)) {
                val id = runCatching { chip.resourceName }.getOrNull() ?: continue
                if (id in picked || picked.size >= 2) continue
                chip.click()
                picked += id
                Thread.sleep(300)
            }
            if (picked.size < 2) device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.5f)
        }
        assertEquals("could not pick two subjects", 2, picked.size)
        val continueButton = findScrolling(continueSelector)!!
        assertTrue("Continue stayed off with two subjects", continueButton.isEnabled)
        continueButton.click()
        reachDashboard("saving the subjects")

        assertEquals("subjectSelections holds the wrong number of subjects", 2, subjectCount(teacher.uid))
    }

    /** AND-T-11: an address that already has an account is refused, and no
     *  second account appears. */
    @Test
    fun anAddressInUseIsRefused() {
        val password = "Emulator-${(100_000..999_999).random()}"
        openSignUpForm()
        fillSignUp(appTeacher.email, password, password, agreeToTerms = true)
        submitSignUp()

        val ok = device.wait(Until.findObject(dialogButton), 30_000)
        assertNotNull("signing up with an address in use showed no error", ok)
        val screen = screenText()
        println("[ProTeacherSignUpTest] in use: $screen")
        assertTrue("the error does not say the address is in use: $screen", inUseMessages.any { screen.contains(it) })
        ok.click()
        // The keyboard may have scrolled the address field off the top.
        assertTrue("the sign-up form is gone", device.wait(Until.hasObject(By.res("sign_up_continue")), 10_000))
        assertFalse("an address in use went on to the profile", device.hasObject(By.res("complete_profile_full_name")))
        assertEquals("the address has more than one account", 1, backend.users(appTeacher.email).size)
        assertTrue("the existing account no longer signs in", backend.canSignIn(appTeacher))
    }

    /** AND-T-12: each invalid form keeps Continue off and says why under the
     *  field (or the terms box), with no dialog over it; tapping the disabled
     *  Continue does nothing, and none of them creates an account. */
    @Test
    fun invalidSignUpsAreRefused() {
        val email = backend.newEmail("signup.invalid")
        openSignUpForm()
        // Each message in English and in Hebrew, whichever the app runs in.
        val cases = listOf(
            listOf("a bad address", "not-an-address", "Emulator-123456", "Emulator-123456", "yes",
                "Enter a valid email address.", "הזן כתובת אימייל תקינה."),
            listOf("a short password", email, "12345", "12345", "yes",
                "Must be at least 6 characters.", "חייב להכיל לפחות 6 תווים."),
            listOf("a mismatched confirmation", email, "Emulator-123456", "Emulator-654321", "yes",
                "Passwords do not match.", "הסיסמאות אינן תואמות."),
            listOf("unaccepted terms", email, "Emulator-123456", "Emulator-123456", "no",
                "Accept the terms to continue", "יש לאשר את התנאים כדי להמשיך"),
        )
        for (case in cases) {
            val (described, address, password, confirmation, agree) = case
            val message = Pattern.compile(Pattern.quote(case[5]) + "|" + Pattern.quote(case[6]))
            fillSignUp(address, password, confirmation, agreeToTerms = agree == "yes")
            println("[ProTeacherSignUpTest] $described: ${screenText()}")
            // The message can sit above the part of the form left in view.
            val shown = findScrolling(By.text(message)) ?: findScrolling(By.text(message), Direction.UP)
            assertNotNull("$described: no \"${case[5]}\" on the form", shown)
            val continueButton = findScrolling(By.res("sign_up_continue"))
            assertNotNull("$described: no Continue", continueButton)
            assertFalse("$described: Continue was on", continueButton!!.isEnabled)
            continueButton.click()
            assertNull("$described: a dialog covered the form", device.wait(Until.findObject(dialogButton), 3_000))
            assertFalse("$described: went on to the profile", device.hasObject(By.res("complete_profile_full_name")))
        }
        assertTrue("an invalid sign-up created an account", backend.users(email).isEmpty())
    }

    /** AND-T-13: a student account is turned away with the notice about the
     *  student app, signed out, and left a student. */
    @Test
    fun aStudentAccountIsTurnedAway() {
        submitLogin(student.email, student.password)

        val ok = device.wait(Until.findObject(dialogButton), 60_000)
        if (ok == null) {
            capture("student-in-pro-teacher")
            fail("a student account got no notice: ${screenText()}")
        }
        println("[ProTeacherSignUpTest] notice: ${screenText()}")
        assertFalse("a student account reached the dashboard", device.hasObject(By.res("availability_toggle")))
        ok!!.click()
        assertTrue(
            "the notice did not leave the app on the welcome screen",
            device.wait(Until.hasObject(By.res("welcome_log_in")), 15_000)
        )
        assertEquals("student", backend.strings("users/${student.uid}")?.get("role"))
        assertNull("the student account stayed signed in", FirebaseAuth.getInstance().currentUser)
    }

    /** AND-T-03: Log in and Create account offer Google, and no Apple. */
    @Test
    fun onlyGoogleIsOfferedNoApple() {
        // The scene leaves the login form open.
        assertNotNull("Log in offers no Google", findScrolling(By.res("log_in_google")))
        assertFalse("Log in offers Apple on Android", device.hasObject(By.res("log_in_apple")))

        openSignUpForm()
        assertNotNull("Create account offers no Google", findScrolling(By.res("sign_up_google")))
        assertFalse("Create account offers Apple on Android", device.hasObject(By.res("sign_up_apple")))
    }

    /** AND-G-11: the Terms and Privacy links under the agreement each open
     *  their own page. */
    @Test
    fun signUpAgreementLinksOpenTheirPages() {
        openSignUpForm()
        val pages = mutableMapOf<String, List<String>>()
        val marks = Regex("[\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]")
        for (link in listOf("sign_up_terms_link", "sign_up_privacy_link")) {
            val button = findScrolling(By.res(link)) ?: run { capture(link); fail("no $link under the agreement"); return }
            val title = (button.findObject(By.textContains(""))?.text ?: button.text ?: "").replace(marks, "").trim()
            button.click()
            val open = device.wait(Until.findObject(By.res("about_open_link")), 15_000)
            assertNotNull("$link opened no page", open)
            val shown = device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }
                .map { it.replace(marks, "").trim() }.filter { it.isNotEmpty() && !Regex("^\\d{1,2}:\\d{2}$").matches(it) }
            pages[link] = shown
            // The Terms page is titled with the EULA string, not the link's
            // "Terms of Service": the same page under two names. Privacy is
            // titled as its link.
            if (link == "sign_up_privacy_link") assertTrue("$link opened a page not titled \"$title\": $shown", title in shown)
            open!!.click()
            assertTrue("$link's page did not open in the browser",
                device.wait(Until.gone(By.pkg(context.packageName).depth(0)), 15_000))
            device.pressBack()
            assertTrue("Back from the browser did not return", device.wait(Until.hasObject(By.res("about_open_link")), 15_000))
            device.pressBack() // the page, back to sign-up
            assertTrue("Back from the page did not return to sign-up", device.wait(Until.hasObject(By.res("sign_up_email")), 15_000))
        }
        assertTrue("Terms and Privacy opened the same page: $pages", pages["sign_up_terms_link"] != pages["sign_up_privacy_link"])
    }

    /** AND-T-16: Back on a later step goes one step back; on the first step it
     *  asks before signing out, and only then returns to the welcome screen. */
    @Test
    fun backInOnboardingStepsBackAndAsksBeforeSigningOut() {
        val email = backend.newEmail("signup.back")
        val password = "Emulator-${(100_000..999_999).random()}"
        openSignUpForm()
        fillSignUp(email, password, password, agreeToTerms = true)
        submitSignUp()
        reachProfile()

        // The first step asks; Cancel stays.
        pressBackForDialog("the profile step")
        device.findObject(By.res("dialog_cancel_button")).click()
        assertTrue("Cancel left the profile step", device.wait(Until.hasObject(By.res("complete_profile_full_name")), 10_000))
        assertNotNull("cancelling signed the teacher out", FirebaseAuth.getInstance().currentUser)

        // A later step goes back one step.
        type("Back Teacher", into = "complete_profile_full_name")
        type("0521234567", into = "complete_profile_phone")
        findScrolling(By.res("complete_profile_continue"))!!.click()
        device.wait(Until.findObject(dialogButton), 15_000)?.click() // no payout method yet: go on
        assertTrue("finishing the profile did not leave it",
            device.wait(Until.gone(By.res("complete_profile_full_name")), 30_000))
        device.pressBack()
        assertTrue("Back on the next step did not return to the profile",
            device.wait(Until.hasObject(By.res("complete_profile_full_name")), 15_000))

        // And on the first step, confirming signs out to the welcome screen.
        pressBackForDialog("the profile step again")
        device.findObject(dialogButton).click()
        assertTrue("confirming did not return to the welcome screen",
            device.wait(Until.hasObject(By.res("welcome_log_in")), 20_000))
        assertNull("still signed in on the welcome screen", FirebaseAuth.getInstance().currentUser)
    }

    /** Back until the sign-out question shows: the first Back may only close
     *  the keyboard. */
    private fun pressBackForDialog(where: String) {
        repeat(2) {
            device.pressBack()
            if (device.wait(Until.hasObject(By.res("dialog_cancel_button")), 4_000)) return
        }
        capture("back-dialog")
        fail("Back on $where did not ask before signing out: ${screenText()}")
    }

    // Steps

    /** From the login form, back to the welcome screen and on to sign-up. */
    private fun openSignUpForm() {
        device.pressBack()
        repeat(5) {
            if (device.hasObject(By.res("sign_up_email"))) return@repeat
            device.wait(Until.findObject(By.res("welcome_sign_up")), 15_000)?.click()
            device.wait(Until.hasObject(By.res("sign_up_email")), 5_000)
        }
        assertTrue("the sign-up form did not open", device.wait(Until.hasObject(By.res("sign_up_email")), 10_000))
        termsChecked = false
    }

    private fun fillSignUp(email: String, password: String, confirmation: String, agreeToTerms: Boolean) {
        // A previous case can leave the form scrolled past the address.
        findScrolling(By.clazz("android.widget.EditText").hasAncestor(By.res("sign_up_email")), Direction.UP)
        type(email, into = "sign_up_email")
        type(password, into = "sign_up_password")
        type(confirmation, into = "sign_up_confirm_password")
        if (termsChecked != agreeToTerms) {
            val box = findScrolling(By.res("sign_up_terms"))
            assertNotNull("no terms box", box)
            box!!.click()
            termsChecked = agreeToTerms
        }
    }

    private fun submitSignUp() {
        val button = findScrolling(By.res("sign_up_continue"))
        assertNotNull("no sign-up Continue", button)
        button!!.click()
    }

    private fun reachProfile() {
        if (!device.wait(Until.hasObject(By.res("complete_profile_full_name")), 60_000)) {
            capture("profile")
            fail("signing up did not reach the profile step: ${screenText()}")
        }
    }

    private fun profileContinueEnabled(): Boolean {
        Thread.sleep(500)
        return findScrolling(By.res("complete_profile_continue"))!!.isEnabled
    }

    /** The dashboard, past the permissions step a new teacher may be shown. */
    private fun reachDashboard(after: String) {
        val deadline = System.currentTimeMillis() + 90_000
        while (System.currentTimeMillis() < deadline && !device.hasObject(By.res("availability_toggle"))) {
            val skip = device.findObject(By.res("permissions_setup_skip"))
            when {
                skip != null -> runCatching { skip.click() }
                // The permissions step can be taller than the screen, with its
                // Skip below the fold.
                else -> runCatching { device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f) }
            }
            Thread.sleep(1_000)
        }
        if (!device.hasObject(By.res("availability_toggle"))) {
            capture("dashboard")
            fail("$after did not reach the dashboard: ${screenText()}")
        }
    }

    private fun subjectCount(uid: String): Int {
        val areas = backend.fields("users/$uid")
            ?.optJSONObject("subjectSelections")?.optJSONObject("mapValue")?.optJSONObject("fields")
            ?: return 0
        return areas.keys().asSequence().sumOf { key ->
            areas.getJSONObject(key).optJSONObject("arrayValue")?.optJSONArray("values")?.length() ?: 0
        }
    }

    /** Finds `selector`, scrolling for it a few times. */
    private fun findScrolling(selector: BySelector, direction: Direction = Direction.DOWN): UiObject2? {
        var found = device.wait(Until.findObject(selector), 5_000)
        repeat(6) {
            if (found != null) return@repeat
            device.findObject(By.scrollable(true))?.scroll(direction, 0.8f)
            found = device.wait(Until.findObject(selector), 2_000)
        }
        return found
    }
}
