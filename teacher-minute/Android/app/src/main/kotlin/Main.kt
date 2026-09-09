package teacher.minute

import skip.lib.*
import skip.model.*
import skip.foundation.*
import skip.ui.*

import android.Manifest
import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.OnBackPressedCallback
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.MaterialTheme
import androidx.core.app.ActivityCompat

internal val logger: SkipLogger = SkipLogger(subsystem = "teacher.minute", category = "TeacherMinute")

private typealias AppRootView = TeacherMinuteRootView
private typealias AppDelegate = TeacherMinuteAppDelegate

/// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
open class AndroidAppMain: Application {
    constructor() {
    }

    override fun onCreate() {
        super.onCreate()
        logger.info("starting app")
        ProcessInfo.launch(applicationContext)
        AndroidLocaleManager.initialize(this)
        AndroidLocalNotificationManager.initialize(this)
        AndroidPushTokenManager.initialize(this)
        AppDelegate.shared.onInit()
    }

    companion object {
    }
}

/// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
open class MainActivity: AppCompatActivity {
    constructor() {
    }

    private var blockBackCallback: OnBackPressedCallback? = null

    /**
     * Back handling while a lesson is on screen. The lesson is a pushed
     * navigation destination, and Compose Navigation registers its own back
     * callback from inside `setContent` — added after `blockBackCallback`, so
     * it wins the dispatcher and pops the lesson out from under a teacher or
     * student who is still connected and being billed. This callback is added
     * only when a lesson starts, which puts it last of all and so first to run.
     */
    private var sessionBackCallback: OnBackPressedCallback? = null

    /**
     * Back handling while an onboarding step is on screen. Onboarding is a
     * stack of steps the user should be able to walk back through, and backing
     * out of the first one means signing out — decisions the app makes, so this
     * callback only forwards the press.
     */
    private var onboardingBackCallback: OnBackPressedCallback? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        currentActivity = this
        logger.info("starting activity")
        UIApplication.launch(this)
        enableEdgeToEdge()

        val callback = object : OnBackPressedCallback(false) {
            override fun handleOnBackPressed() {
                logger.info("[BackNav] suppressing system back on main tabs")
                moveTaskToBack(true)
            }
        }
        blockBackCallback = callback
        onBackPressedDispatcher.addCallback(this, callback)

        // Must happen in onCreate: GooglePayLauncher registers an Activity Result
        // callback, which Android rejects once the activity is STARTED.
        AndroidGooglePayManager.register(this)

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }

        AppDelegate.shared.onLaunch()

        // Example of requesting permissions on startup.
        // These must match the permissions in the AndroidManifest.xml file.
        //let permissions = listOf(
        //    Manifest.permission.ACCESS_COARSE_LOCATION,
        //    Manifest.permission.ACCESS_FINE_LOCATION
        //    Manifest.permission.CAMERA,
        //    Manifest.permission.WRITE_EXTERNAL_STORAGE,
        //)
        //let requestTag = 1
        //ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
    }

    override fun onStart() {
        logger.info("onStart")
        super.onStart()
    }

    // PayPal returns from the browser as a new App Link intent. singleTask
    // launchMode (see AndroidManifest) routes it here rather than starting a
    // second MainActivity, so the pending vault request can be matched.
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        AndroidPayPalManager.handleReturnToApp(this, intent)
    }

    override fun onResume() {
        super.onResume()
        // Covers the case where the activity was recreated while the buyer was
        // in the browser, so the return arrived as the launch intent rather
        // than through onNewIntent.
        AndroidPayPalManager.handleReturnToApp(this, intent)
        isResumed = true
        // Once the app is in front the invite poll takes over and the overlay is
        // how an invite gets answered, so any invite notification still sitting
        // in the shade can only lead somewhere stale.
        AndroidIncomingQuestionNotifier.cancelAll(this)
        AppDelegate.shared.onResume()
    }

    override fun onPause() {
        super.onPause()
        isResumed = false
        AppDelegate.shared.onPause()
    }

    override fun onStop() {
        super.onStop()
        AppDelegate.shared.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (currentActivity === this) {
            currentActivity = null
        }
        AppDelegate.shared.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (AndroidGoogleSignInManager.handleActivityResult(requestCode, resultCode, data)) {
            return
        }
        if (AndroidImagePickerManager.handleActivityResult(requestCode, resultCode, data)) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        AppDelegate.shared.onLowMemory()
    }

    override fun onRestart() {
        logger.info("onRestart")
        super.onRestart()
    }

    override fun onSaveInstanceState(outState: android.os.Bundle): Unit = super.onSaveInstanceState(outState)

    override fun onRestoreInstanceState(bundle: android.os.Bundle) {
        // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
        logger.info("onRestoreInstanceState")
        super.onRestoreInstanceState(bundle)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
        if (AndroidPermissionManager.handleRequestPermissionsResult(requestCode, permissions, grantResults)) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        logger.info("onRequestPermissionsResult: ${requestCode}")
    }

    companion object {
        @JvmStatic
        var currentActivity: MainActivity? = null

        /**
         * Whether the activity is actually in front, which `currentActivity`
         * does not answer — that outlives a backgrounded activity and is only
         * cleared on destroy. Invite notifications are suppressed while the app
         * is resumed, because the dashboard's own poll already shows the
         * overlay, so this has to distinguish resumed from merely alive.
         */
        @JvmStatic
        var isResumed: Boolean = false

        @JvmStatic
        fun setSystemBackBlocked(blocked: Boolean) {
            val activity = currentActivity ?: return
            activity.runOnUiThread {
                activity.blockBackCallback?.isEnabled = blocked
            }
        }

        /**
         * Routes the system back button to the onboarding step on screen.
         *
         * Registered while onboarding is up, which puts it after the callback
         * Compose Navigation adds for the destination and so first to run —
         * the same ordering trick [setSessionBackBlocked] relies on. Without
         * it, back either popped out of onboarding without asking or, with the
         * tab bar's blocker still installed, backgrounded the app.
         */
        @JvmStatic
        fun setOnboardingBackHandling(enabled: Boolean) {
            val activity = currentActivity ?: return
            activity.runOnUiThread {
                if (enabled) {
                    if (activity.onboardingBackCallback != null) {
                        return@runOnUiThread
                    }
                    val callback = object : OnBackPressedCallback(true) {
                        override fun handleOnBackPressed() {
                            logger.info("[BackNav] onboarding back — handing to the app")
                            OnboardingBackBridge.shared.handleBack()
                        }
                    }
                    activity.onboardingBackCallback = callback
                    activity.onBackPressedDispatcher.addCallback(activity, callback)
                } else {
                    activity.onboardingBackCallback?.remove()
                    activity.onboardingBackCallback = null
                }
            }
        }

        /**
         * Takes back away from the navigation stack for the duration of a
         * lesson, so it backgrounds the app — what it already does on the tabs
         * — instead of popping a live session.
         */
        @JvmStatic
        fun setSessionBackBlocked(blocked: Boolean) {
            val activity = currentActivity ?: return
            activity.runOnUiThread {
                if (blocked) {
                    if (activity.sessionBackCallback != null) {
                        return@runOnUiThread
                    }
                    val callback = object : OnBackPressedCallback(true) {
                        override fun handleOnBackPressed() {
                            logger.info("[BackNav] suppressing system back during live session")
                            activity.moveTaskToBack(true)
                        }
                    }
                    activity.sessionBackCallback = callback
                    activity.onBackPressedDispatcher.addCallback(activity, callback)
                } else {
                    activity.sessionBackCallback?.remove()
                    activity.sessionBackCallback = null
                }
            }
        }
    }
}

@Composable
internal fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f

    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }

    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(
            statusBarStyle = style,
            navigationBarStyle = style
        )
        onDispose { }
    }
}

@Composable
internal fun PresentationRootView(context: ComposeContext) {
    val colorScheme = if (isSystemInDarkTheme()) ColorScheme.dark else ColorScheme.light
    PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
        SyncSystemBarsWithTheme()
        val contentContext = ctx.content()
        // No status-bar inset here: SkipUI's `PresentationRoot` has already
        // padded this content by `WindowInsets.safeDrawing`, so adding one
        // leaves an empty status-bar-tall band above every screen.
        Box(
            modifier = ctx.modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            AppRootView().Compose(context = contentContext)
        }
    }
}
