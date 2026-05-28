package teacher.minute

import android.util.Log
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue

object AndroidPushTokenManager {
    private const val TAG = "PushToken"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"

    @JvmStatic
    fun writeToken(token: String, uid: String, isTeacher: Boolean) {
        val updates = mapOf<String, Any>(
            "fcmToken" to token,
            "fcmTokenUpdatedAt" to ServerValue.TIMESTAMP
        )

        write("users/$uid", updates)
        if (isTeacher) {
            write("teachers/$uid", updates)
        }
    }

    private fun write(path: String, values: Map<String, Any>) {
        FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference(path)
            .updateChildren(values)
            .addOnSuccessListener {
                Log.i(TAG, "Wrote FCM token path=$path keys=${values.keys}")
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed writing FCM token path=$path", error)
            }
    }
}
