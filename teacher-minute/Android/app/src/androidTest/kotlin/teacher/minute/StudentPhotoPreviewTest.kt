package teacher.minute

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import com.google.firebase.auth.FirebaseAuth
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * IT-24: a photo chosen from the gallery in Ask → Text shows in the preview,
 * not as a black tile.
 *
 * A solid red photo is put in the gallery, picked through the system's
 * document picker, and the preview's pixels are read back from a screenshot.
 *
 *     ./gradlew :app:connectedStudentDebugAndroidTest \
 *       -Pandroid.testInstrumentationRunnerArguments.class=teacher.minute.StudentPhotoPreviewTest
 */
@RunWith(AndroidJUnit4::class)
class StudentPhotoPreviewTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)
    private val photoName = "it24-red-${System.currentTimeMillis()}.jpg"
    private var photoUri: android.net.Uri? = null

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
        photoUri = putRedPhotoInGallery()
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 30_000)
    }

    @After
    fun tearDown() {
        photoUri?.let { uri -> runCatching { context.contentResolver.delete(uri, null, null) } }
    }

    @Test
    fun aLibraryPhotoShowsInThePreview() {
        signedInStudent()
        val tab = device.wait(Until.findObject(By.res("question_home_mode_text")), 20_000)
            ?: failWithScreen("text-tab", "no Text tab at home")
        tab.click()

        val add = device.wait(Until.findObject(By.res("add_question_photo")), 15_000)
            ?: failWithScreen("add", "no add-photo button in the Text panel")
        add.click()
        val library = device.wait(Until.findObject(By.text("Choose from Library")), 10_000)
            ?: failWithScreen("source", "the photo source dialog has no library option")
        library.click()

        pickInDocumentsUi()

        val preview = device.wait(Until.findObject(By.res("delete_question_photo")), 60_000)
            ?: failWithScreen("preview", "the photo never finished attaching")
        // The thumbnail is loaded after the upload switches the tile over.
        Thread.sleep(3_000)
        val bounds = device.findObject(By.res("delete_question_photo"))?.visibleBounds ?: preview.visibleBounds
        val shot = java.io.File(shotDir(), "it24-preview.png")
        device.takeScreenshot(shot)
        val screen = BitmapFactory.decodeFile(shot.path)
        // A corner of the tile, clear of the delete icon in its middle.
        val x = bounds.left + bounds.width() / 6
        val y = bounds.top + bounds.height() / 6
        val pixel = screen.getPixel(x, y)
        println("[StudentPhotoPreviewTest] preview $bounds pixel at ($x,$y) = ${Integer.toHexString(pixel)}")
        assertTrue(
            "the preview is not the red photo: pixel #${Integer.toHexString(pixel)} at ($x,$y) in $bounds",
            Color.red(pixel) > 180 && Color.green(pixel) < 90 && Color.blue(pixel) < 90
        )
    }

    // Steps

    /** A solid red JPEG in the gallery, newest, so it is first in Recent. */
    private fun putRedPhotoInGallery(): android.net.Uri {
        val bitmap = Bitmap.createBitmap(800, 600, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawColor(Color.rgb(230, 20, 20))
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, photoName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/TIM-test")
        }
        val uri = context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: error("could not add a photo to the gallery")
        context.contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }
        return uri
    }

    /**
     * The system picker opens on Recent, the newest photo first; each item is
     * described as "<name>, <size>, <time>".
     */
    private fun pickInDocumentsUi() {
        val item = device.wait(Until.findObject(By.descStartsWith(photoName)), 30_000)
            ?: failWithScreen("picker", "the photo never showed in the system picker")
        item.click()
    }

    private fun signedInStudent() {
        val student = backend.createAccount("photo.student")
        backend.merge(
            "users/${student.uid}",
            mapOf("role" to "student", "fullName" to "Photo Student", "remainingMinutes" to 60, "totalMinutes" to 60)
        )
        val start = device.wait(Until.findObject(By.res("student_intro_start")), 60_000)
            ?: failWithScreen("intro", "the intro's Start never appeared")
        start.click()
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline && !device.wait(Until.gone(By.res("student_intro_start")), 3_000)) {
            runCatching { device.findObject(By.res("student_intro_start"))?.click() }
        }
        if (!waitForHome(60_000)) failWithScreen("home", "Start did not reach home")

        device.findObject(By.res("side_menu_button"))?.click() ?: failWithScreen("menu", "no menu button")
        val logIn = device.wait(Until.findObject(By.res("side_menu_log_in")), 15_000)
            ?: failWithScreen("menu", "no Log in in a guest's menu")
        logIn.click()
        if (!device.wait(Until.hasObject(By.res("email_input")), 20_000)) failWithScreen("login", "the login form did not open")
        type(student.email, into = "email_input")
        type(student.password, into = "password_input")
        device.findObject(By.res("login_submit")).click()
        if (!device.wait(Until.gone(By.res("email_input")), 90_000) || !waitForHome(90_000)) {
            failWithScreen("login", "logging in did not reach home")
        }
    }

    private fun waitForHome(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            device.findObject(By.res("student_tutorial_skip"))?.let { runCatching { it.click() } }
            device.findObject(By.res("permissions_setup_skip"))?.let { runCatching { it.click() } }
            device.findObject(By.res("verify_email_not_now"))?.let { runCatching { it.click() } }
            if (device.hasObject(By.res("question_home_mode_text")) && !device.hasObject(By.res("student_tutorial_skip")) &&
                !device.hasObject(By.res("email_input"))
            ) return true
            Thread.sleep(1_000)
        }
        return false
    }

    private fun type(text: String, into: String) {
        val tagged = device.wait(Until.findObject(By.res(into)), 20_000) ?: failWithScreen(into, "no $into")
        val field: UiObject2 = tagged.findObject(By.clazz("android.widget.EditText")) ?: tagged
        field.click()
        field.text = text
    }

    private fun shotDir(): java.io.File = context.getExternalFilesDir(null) ?: context.filesDir

    private fun screenText(): String =
        device.findObjects(By.textContains("")).mapNotNull { runCatching { it.text }.getOrNull() }
            .filter { it.isNotBlank() }.joinToString(" | ")

    private fun failWithScreen(name: String, message: String): Nothing {
        device.takeScreenshot(java.io.File(shotDir(), "it24-$name.png"))
        java.io.File(shotDir(), "it24-$name.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        fail("$message: ${screenText()} (in ${device.currentPackageName})")
        throw AssertionError(message)
    }
}
