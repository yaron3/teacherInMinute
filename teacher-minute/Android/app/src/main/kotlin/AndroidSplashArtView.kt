package teacher.minute

import android.view.View
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import skip.ui.ComposeContext
import skip.ui.ComposeView

/**
 * The launch splash's art — gradient, glow and logo — for `LaunchSplashView`,
 * drawn from res/drawable/splash_background.xml, the same drawable as the window
 * Android shows while the app starts. SwiftUI images load asynchronously on
 * Android, so drawing the art with them left the screen without it for a moment
 * when the app replaced that window; a drawable is there on the first frame.
 */
object AndroidSplashArtView {
    @JvmStatic
    fun create(): ComposeView {
        return ComposeView { context: ComposeContext ->
            AndroidView(
                factory = { androidContext ->
                    View(androidContext).apply {
                        background = ContextCompat.getDrawable(androidContext, R.drawable.splash_background)
                    }
                },
                modifier = context.modifier.fillMaxSize()
            )
        }
    }
}
