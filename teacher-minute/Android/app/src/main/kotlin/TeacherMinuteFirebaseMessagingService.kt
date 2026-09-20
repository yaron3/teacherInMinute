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

    /**
     * Called for every push while the app is in the foreground, and for
     * data-only pushes at any time. The backend sends three kinds
     * (functions/src/fcm.ts):
     *
     *  - `incoming_question` is data-only, so nothing appears unless we post it.
     *    This is the teacher's only signal once the app is backgrounded, since
     *    the invite poll stops with the app.
     *  - `question_accepted` and `no_match` carry a `notification` payload, so
     *    the system posts them itself while the app is away. Posting again here
     *    would duplicate them.
     */
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.data
        val type = data["type"]
        Log.i(TAG, "FCM message received from=${message.from} type=$type")

        when (type) {
            "incoming_question" -> AndroidIncomingQuestionNotifier.handle(applicationContext, data)
            else -> Unit
        }
    }

    companion object {
        private const val TAG = "TeacherMinuteFCM"
    }
}
