package teacher.minute

import android.util.Log
import io.livekit.android.ConnectOptions
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import kotlinx.coroutines.runBlocking

object AndroidLiveKitManager {
    private const val TAG = "AndroidLiveKit"

    private val lock = Any()
    private var room: Room? = null

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
                val videoEnabled = newRoom.localParticipant.setCameraEnabled(true)
                if (!videoEnabled) {
                    newRoom.disconnect()
                    throw IllegalStateException("LiveKit camera enable failed")
                }
            }

            synchronized(lock) {
                room = newRoom
            }
            Log.i(TAG, "Connected room=$roomName tracks=${newRoom.localParticipant.trackPublications.size}")
        }
    }

    @JvmStatic
    fun disconnect() {
        runBlocking {
            disconnectExisting()
        }
    }

    private fun disconnectExisting() {
        val existing = synchronized(lock) {
            val current = room
            room = null
            current
        } ?: return

        Log.i(TAG, "Disconnecting current room")
        existing.disconnect()
    }
}
