package teacher.minute

import android.util.Log
import androidx.compose.runtime.mutableStateOf
import io.livekit.android.ConnectOptions
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.participant.ConnectionQuality
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

object AndroidLiveKitManager {
    private const val TAG = "AndroidLiveKit"

    private val lock = Any()
    private var room: Room? = null
    private var eventsScope: CoroutineScope? = null

    val remoteCameraTrack = mutableStateOf<VideoTrack?>(null)
    val localCameraTrack = mutableStateOf<VideoTrack?>(null)

    fun currentRoom(): Room? = synchronized(lock) { room }

    /**
     * Whether this room is actually sending a camera. A video lesson whose
     * camera would not start is allowed to run on audio alone, and this is how
     * the Swift layer finds out that is what happened.
     */
    @JvmStatic
    fun isCameraPublished(): Boolean = localCameraTrack.value != null

    /**
     * The worst connection quality in the room, as one of "lost", "poor",
     * "good" or "unknown". A room that is re-establishing itself counts as
     * lost — nothing is getting through while it does.
     */
    @JvmStatic
    fun connectionQuality(): String {
        val current = currentRoom() ?: return "unknown"
        if (current.state == Room.State.RECONNECTING || current.state == Room.State.CONNECTING) {
            return "lost"
        }
        val qualities = mutableListOf(current.localParticipant.connectionQuality)
        current.remoteParticipants.values.mapTo(qualities) { it.connectionQuality }
        return when {
            qualities.any { it == ConnectionQuality.LOST } -> "lost"
            qualities.any { it == ConnectionQuality.POOR } -> "poor"
            qualities.any { it == ConnectionQuality.GOOD || it == ConnectionQuality.EXCELLENT } -> "good"
            else -> "unknown"
        }
    }

    @JvmStatic
    fun connect(serverUrl: String, roomName: String, token: String, enableVideo: Boolean) {
        if (serverUrl.isBlank() || roomName.isBlank() || token.isBlank()) {
            throw IllegalArgumentException("Missing LiveKit server URL, room, or token")
        }

        val appContext = MainActivity.currentActivity?.applicationContext
            ?: throw IllegalStateException("No active Android activity for LiveKit")

        runBlocking {
            disconnectExisting()

            Log.i(TAG, "Connecting room=$roomName video=$enableVideo url=$serverUrl")
            val newRoom = LiveKit.create(appContext)
            newRoom.connect(
                url = serverUrl,
                token = token,
                options = ConnectOptions(audio = true, video = enableVideo)
            )

            val audioEnabled = newRoom.localParticipant.setMicrophoneEnabled(true)
            if (!audioEnabled) {
                newRoom.disconnect()
                throw IllegalStateException("LiveKit microphone enable failed")
            }

            if (enableVideo) {
                // A camera that will not start (emulator, hardware in use,
                // capture error) must not take the lesson down with it: publish
                // what we can and let the session run audio-only.
                try {
                    val videoEnabled = newRoom.localParticipant.setCameraEnabled(true)
                    if (!videoEnabled) {
                        Log.e(TAG, "Camera enable returned false, continuing audio-only")
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "Camera enable failed, continuing audio-only: ${t.message}")
                }
            }

            synchronized(lock) {
                room = newRoom
            }
            refreshTracks(newRoom)
            startEventListener(newRoom)
            Log.i(TAG, "Connected room=$roomName tracks=${newRoom.localParticipant.trackPublications.size}")
        }
    }

    @JvmStatic
    fun disconnect() {
        runBlocking {
            disconnectExisting()
        }
    }

    @JvmStatic
    fun setMicrophoneEnabled(enabled: Boolean) {
        val current = currentRoom() ?: return
        runBlocking {
            try {
                current.localParticipant.setMicrophoneEnabled(enabled)
                Log.i(TAG, "setMicrophoneEnabled=$enabled")
            } catch (t: Throwable) {
                Log.e(TAG, "setMicrophoneEnabled failed: ${t.message}")
            }
        }
    }

    @JvmStatic
    fun setCameraEnabled(enabled: Boolean) {
        val current = currentRoom() ?: return
        runBlocking {
            try {
                current.localParticipant.setCameraEnabled(enabled)
                Log.i(TAG, "setCameraEnabled=$enabled")
                refreshTracks(current)
            } catch (t: Throwable) {
                Log.e(TAG, "setCameraEnabled failed: ${t.message}")
            }
        }
    }

    private fun startEventListener(target: Room) {
        eventsScope?.cancel()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        eventsScope = scope
        scope.launch {
            target.events.collect { event ->
                when (event) {
                    is RoomEvent.TrackSubscribed,
                    is RoomEvent.TrackUnsubscribed,
                    is RoomEvent.TrackPublished,
                    is RoomEvent.TrackUnpublished,
                    is RoomEvent.TrackMuted,
                    is RoomEvent.TrackUnmuted,
                    is RoomEvent.ParticipantConnected,
                    is RoomEvent.ParticipantDisconnected -> refreshTracks(target)
                    else -> {}
                }
            }
        }
    }

    private fun refreshTracks(target: Room) {
        val local = target.localParticipant.trackPublications.values
            .firstOrNull { it.source == Track.Source.CAMERA }
            ?.track as? VideoTrack
        val remote = target.remoteParticipants.values
            .flatMap { it.trackPublications.values }
            .firstOrNull { it.source == Track.Source.CAMERA && it.subscribed && !it.muted }
            ?.track as? VideoTrack
        localCameraTrack.value = local
        remoteCameraTrack.value = remote
        Log.i(TAG, "refreshTracks local=${local != null} remote=${remote != null}")
    }

    private fun disconnectExisting() {
        val existing = synchronized(lock) {
            val current = room
            room = null
            current
        }
        eventsScope?.cancel()
        eventsScope = null
        localCameraTrack.value = null
        remoteCameraTrack.value = null
        existing ?: return

        Log.i(TAG, "Disconnecting current room")
        existing.disconnect()
    }
}
