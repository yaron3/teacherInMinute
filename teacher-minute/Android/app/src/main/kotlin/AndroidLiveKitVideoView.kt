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
import io.livekit.android.renderer.TextureViewRenderer
import io.livekit.android.room.track.VideoTrack
import livekit.org.webrtc.RendererCommon.ScalingType
import skip.ui.ComposeContext
import skip.ui.ComposeView

/**
 * Factory that produces a Skip [ComposeView] which renders a LiveKit camera
 * track using a native [TextureViewRenderer]. Mirrors the iOS
 * `SwiftUIVideoView` integration so the Swift layer can drop one of these
 * into the view hierarchy via `JavaBackedView`.
 */
object AndroidLiveKitVideoView {
    private const val MODE_REMOTE = "remote"
    private const val MODE_LOCAL = "local"

    @JvmStatic
    fun create(mode: String, mirror: Boolean): ComposeView {
        return ComposeView { context: ComposeContext ->
            LiveKitVideoContent(mode = mode, mirror = mirror, modifier = context.modifier)
        }
    }

    /**
     * The [ComposeContext] modifier is the slot SwiftUI laid this view out in —
     * the share of the session column the feed was given, the 96x132 frame of
     * the self preview. Dropping it and filling the parent instead is how the
     * feed came to cover the whole screen, tab strip included, so it has to be
     * applied before anything of ours.
     */
    @Composable
    private fun LiveKitVideoContent(mode: String, mirror: Boolean, modifier: Modifier) {
        val track: VideoTrack? = when (mode) {
            MODE_REMOTE -> AndroidLiveKitManager.remoteCameraTrack.value
            MODE_LOCAL -> AndroidLiveKitManager.localCameraTrack.value
            else -> null
        }
        Box(modifier = modifier.fillMaxSize().background(Color.Black)) {
            if (track != null) {
                LiveKitTrackRenderer(
                    track = track,
                    mirror = mirror,
                    // The self preview is a small window onto a portrait
                    // camera, so it crops; the remote feed letterboxes, the
                    // way `SwiftUIVideoView(layoutMode: .fit)` does on iOS.
                    scalingType = if (mode == MODE_LOCAL) ScalingType.SCALE_ASPECT_FILL else ScalingType.SCALE_ASPECT_FIT
                )
            }
        }
    }

    /**
     * Renders onto a `TextureView` rather than the `SurfaceView` the LiveKit
     * samples reach for. A `SurfaceView` is composited in its own layer
     * outside the window and punches a hole through everything drawn over it,
     * so two of them cannot be stacked — the self preview never appeared over
     * the remote feed — and neither can be clipped to the rounded corners the
     * session chrome draws around them.
     */
    @Composable
    private fun LiveKitTrackRenderer(track: VideoTrack, mirror: Boolean, scalingType: ScalingType) {
        val room = AndroidLiveKitManager.currentRoom() ?: return
        var renderer by remember(track) { mutableStateOf<TextureViewRenderer?>(null) }

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                val view = TextureViewRenderer(context)
                room.initVideoRenderer(view)
                view.setScalingType(scalingType)
                view.setMirror(mirror)
                track.addRenderer(view)
                renderer = view
                view
            },
            update = { view ->
                view.setScalingType(scalingType)
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
