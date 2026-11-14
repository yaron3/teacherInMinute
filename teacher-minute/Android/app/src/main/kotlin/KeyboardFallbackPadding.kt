package teacher.minute

import android.graphics.Rect
import android.view.ViewTreeObserver
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * How much of the screen the keyboard covers beyond what the window insets
 * already pad for (IT-10).
 *
 * The app draws edge to edge, so Android does not shrink the window for the
 * keyboard; SkipUI pads every screen by `WindowInsets.safeDrawing` instead,
 * which includes the keyboard only when the system reports it as an IME inset.
 * A tester's Tecno phone (HiOS, Android 12) showed the keyboard over the
 * fields with nothing moving, which is what a missing IME inset looks like.
 *
 * This measures the keyboard the old way, from the window's visible frame,
 * and returns the part the insets left uncovered. Where the insets work, as
 * on every emulator, the two agree and this is zero.
 */
@Composable
internal fun keyboardShortfall(): Dp {
    val view = LocalView.current
    val density = LocalDensity.current
    var obscuredPx by remember { mutableIntStateOf(0) }

    fun measure() {
        val root = view.rootView
        val visible = Rect()
        root.getWindowVisibleDisplayFrame(visible)
        val origin = IntArray(2)
        root.getLocationOnScreen(origin)
        val next = maxOf(0, origin[1] + root.height - visible.bottom)
        if (next != obscuredPx) obscuredPx = next
    }

    DisposableEffect(view) {
        val observer = view.rootView.viewTreeObserver
        val listener = ViewTreeObserver.OnGlobalLayoutListener { measure() }
        observer.addOnGlobalLayoutListener(listener)
        onDispose {
            if (observer.isAlive) observer.removeOnGlobalLayoutListener(listener)
        }
    }
    // Without the inset nothing in the window has to lay out again when the
    // keyboard opens, so the listener alone may never hear of it.
    LaunchedEffect(view) {
        while (true) {
            measure()
            delay(300)
        }
    }

    val paddedPx = WindowInsets.safeDrawing.getBottom(density)
    // Screens keep their own room for the navigation bar at the bottom. With
    // the keyboard up that room sits behind the keyboard, so it is not lifted
    // too; otherwise a bar-tall empty band shows above the keys.
    val navigationBarPx = WindowInsets.navigationBars.getBottom(density)
    val shortfallPx = obscuredPx - paddedPx - navigationBarPx
    // The navigation bar and rounding leave small differences either way; a
    // keyboard is far taller than this.
    if (shortfallPx < with(density) { 80.dp.roundToPx() }) return 0.dp
    return with(density) { shortfallPx.toDp() }
}
