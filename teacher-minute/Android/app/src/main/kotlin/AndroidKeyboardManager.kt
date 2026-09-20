package teacher.minute

import android.content.Context
import android.os.Build
import android.os.Looper
import android.util.Log
import android.view.inputmethod.InputMethodManager
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/**
 * The soft keyboard, for the cases SwiftUI's focus state cannot express on
 * Android.
 *
 * SkipUI's `.focused(_:)` only ever *requests* focus — it calls
 * `focusRequester.requestFocus()` when the binding turns true and does nothing
 * when it turns false. So clearing a `@FocusState` leaves the IME on screen, and
 * a panel the app shows in the keyboard's place (the algebra pad) lands on top
 * of the keyboard instead of replacing it.
 *
 * The other direction needs help too: SkipUI hides the keyboard on every
 * navigation push, and a binding-driven `navigationDestination` re-pushes when
 * the navigator reconciles its back stack about a second later. That hide leaves
 * Compose focus untouched, so the focus state still reads as focused and only
 * the keyboard is gone — nothing SwiftUI can say will bring it back, hence
 * [showSoftKeyboard] and [isSoftKeyboardVisible].
 */
object AndroidKeyboardManager {
    private const val TAG = "AndroidKeyboard"

    /**
     * Whether [isSoftKeyboardVisible] can actually answer on this device.
     *
     * The IME only became a queryable inset type in Android 11. The older trick
     * — measuring the gap the keyboard leaves between the window's visible
     * frame and the bottom of the decor view — needs the window to be resized
     * by the keyboard, and this app draws edge to edge and handles the insets
     * in Compose, so the frame never moves and the measurement reads "no
     * keyboard" while the keyboard is on screen. A caller that believed it
     * asked for the keyboard over and over on a Galaxy S8, which is what this
     * exists to prevent: below Android 11 there is no answer, and the honest
     * thing is to say so rather than to guess wrong.
     */
    @JvmStatic
    fun canReportSoftKeyboardVisibility(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
    }

    @JvmStatic
    fun hideSoftKeyboard() {
        val activity = MainActivity.currentActivity ?: return
        activity.runOnUiThread {
            try {
                val focused = activity.currentFocus
                val token = (focused ?: activity.window.decorView).windowToken
                val manager = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
                    as? InputMethodManager
                manager?.hideSoftInputFromWindow(token, 0)
                // Compose keeps its own focus, and SkipUI re-requests focus on
                // every recomposition while the binding is true — a field that
                // still holds focus would pull the keyboard straight back up.
                focused?.clearFocus()
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to hide the soft keyboard", error)
            }
        }
    }

    /**
     * Asks for the keyboard back for whatever already holds focus. Does nothing
     * useful if nothing is focused — this raises the keyboard, it does not
     * decide which field receives it.
     */
    @JvmStatic
    fun showSoftKeyboard() {
        val activity = MainActivity.currentActivity ?: return
        activity.runOnUiThread {
            try {
                val view = activity.currentFocus ?: activity.window.decorView
                WindowCompat.getInsetsController(activity.window, view)
                    .show(WindowInsetsCompat.Type.ime())
                // The insets controller is the modern route and the one that
                // works with Compose's own IME handling; showSoftInput covers
                // the case where the window has no controller yet.
                val manager = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
                    as? InputMethodManager
                manager?.showSoftInput(view, 0)
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to show the soft keyboard", error)
            }
        }
    }

    /**
     * Whether the keyboard is on screen right now.
     *
     * Window insets are only safe to read on the UI thread, and the caller is
     * on the main actor, so this reads them directly rather than hopping and
     * waiting — waiting from the main thread would deadlock. Off the main
     * thread it reports nothing rather than risking a stale read.
     */
    @JvmStatic
    fun isSoftKeyboardVisible(): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            return false
        }
        if (!canReportSoftKeyboardVisibility()) {
            return false
        }
        val activity = MainActivity.currentActivity ?: return false
        return try {
            val insets = ViewCompat.getRootWindowInsets(activity.window.decorView) ?: return false
            insets.isVisible(WindowInsetsCompat.Type.ime())
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to read soft keyboard visibility", error)
            false
        }
    }
}
