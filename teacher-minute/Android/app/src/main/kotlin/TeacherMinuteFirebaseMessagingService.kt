package teacher.minute

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class TeacherMinuteFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.i(TAG, "FCM token refreshed")
        AndroidPushTokenManager.writeRefreshedToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.i(TAG, "FCM message received from=${message.from} dataKeys=${message.data.keys}")
    }

    companion object {
        private const val TAG = "TeacherMinuteFCM"
    }
}
