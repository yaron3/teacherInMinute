package teacher.minute

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.viewinterop.AndroidView
import io.livekit.android.renderer.SurfaceViewRenderer
import io.livekit.android.room.track.VideoTrack
import skip.ui.ComposeContext
import skip.ui.ComposeView

/**
 * Factory that produces a Skip [ComposeView] which renders a LiveKit camera
 * track using the native [SurfaceViewRenderer]. Mirrors the iOS
 * `SwiftUIVideoView` integration so the Swift layer can drop one of these
 * into the view hierarchy via `JavaBackedView`.
 */
object AndroidLiveKitVideoView {
    private const val MODE_REMOTE = "remote"
    private const val MODE_LOCAL = "local"

    @JvmStatic
    fun create(mode: String, mirror: Boolean): ComposeView {
        return ComposeView { _: ComposeContext ->
            LiveKitVideoContent(mode = mode, mirror = mirror)
        }
    }

    @Composable
    private fun LiveKitVideoContent(mode: String, mirror: Boolean) {
        val track: VideoTrack? = when (mode) {
            MODE_REMOTE -> AndroidLiveKitManager.remoteCameraTrack.value
            MODE_LOCAL -> AndroidLiveKitManager.localCameraTrack.value
            else -> null
        }
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            if (track != null) {
                LiveKitTrackRenderer(track = track, mirror = mirror)
            }
        }
    }

    @Composable
    private fun LiveKitTrackRenderer(track: VideoTrack, mirror: Boolean) {
        val room = AndroidLiveKitManager.currentRoom() ?: return
        var renderer by remember(track) { mutableStateOf<SurfaceViewRenderer?>(null) }

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                val view = SurfaceViewRenderer(context)
                room.initVideoRenderer(view)
                view.setMirror(mirror)
                track.addRenderer(view)
                renderer = view
                view
            },
            update = { view ->
                view.setMirror(mirror)
            }
        )

        DisposableEffect(track) {
            onDispose {
                val r = renderer
                if (r != null) {
                    track.removeRenderer(r)
                    r.release()
                    renderer = null
                }
            }
        }
    }
}
