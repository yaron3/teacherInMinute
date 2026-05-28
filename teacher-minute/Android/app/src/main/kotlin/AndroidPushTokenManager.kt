package teacher.minute

import android.content.Context
import android.provider.Settings
import android.util.Log
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue

object AndroidPushTokenManager {
    private const val TAG = "PushToken"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val PREFS_NAME = "teacher_minute_push"
    private const val KEY_UID = "uid"
    private const val KEY_IS_TEACHER = "isTeacher"

    @Volatile
    private var appContext: Context? = null

    @JvmStatic
    fun initialize(context: Context) {
        appContext = context.applicationContext
    }

    @JvmStatic
    fun writeToken(token: String, uid: String, isTeacher: Boolean) {
        rememberRegistration(uid, isTeacher)
        writeTokenToDatabase(token, uid, isTeacher)
    }

    @JvmStatic
    fun writeRefreshedToken(token: String) {
        val registration = currentRegistration()
        if (registration == null) {
            Log.w(TAG, "Skipping refreshed FCM token write; no cached uid/role")
            return
        }
        writeTokenToDatabase(token, registration.uid, registration.isTeacher)
    }

    private fun writeTokenToDatabase(token: String, uid: String, isTeacher: Boolean) {
        val deviceKey = currentDeviceKey()
        val updates = mapOf<String, Any>(
            "fcmToken" to token,
            "fcmTokenUpdatedAt" to ServerValue.TIMESTAMP,
            "devices/$deviceKey/fcmToken" to token,
            "devices/$deviceKey/token" to token,
            "devices/$deviceKey/platform" to "android",
            "devices/$deviceKey/updatedAt" to ServerValue.TIMESTAMP
        )

        write("users/$uid", updates)
        if (isTeacher) {
            write("teachers/$uid", updates)
        }
    }

    private fun currentDeviceKey(): String {
        val context = appContext ?: MainActivity.currentActivity?.applicationContext ?: return "android-device"
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        return "android-${androidId ?: "device"}"
    }

    private fun rememberRegistration(uid: String, isTeacher: Boolean) {
        val context = appContext ?: MainActivity.currentActivity?.applicationContext ?: return
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_UID, uid)
            .putBoolean(KEY_IS_TEACHER, isTeacher)
            .apply()
    }

    private fun currentRegistration(): Registration? {
        val context = appContext ?: MainActivity.currentActivity?.applicationContext ?: return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val uid = prefs.getString(KEY_UID, null)?.takeIf { it.isNotBlank() } ?: return null
        return Registration(uid, prefs.getBoolean(KEY_IS_TEACHER, false))
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

    private data class Registration(
        val uid: String,
        val isTeacher: Boolean
    )
}
