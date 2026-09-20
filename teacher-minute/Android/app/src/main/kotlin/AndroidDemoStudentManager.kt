package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.database.FirebaseDatabase
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Android side of the "simulate an incoming student question" demo tool.
 *
 * The request itself is created by the `simulateDemoQuestion` Cloud Function;
 * this only reads back how far it got while the local AI service handles it.
 */
object AndroidDemoStudentManager {
    private const val TAG = "AndroidDemoStudent"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val TIMEOUT_SECONDS = 15L
    private const val REQUESTS_PATH = "demoStudent/requests"

    /** Reads the current state of a request. Returns "{}" when it is not readable yet. */
    @JvmStatic
    fun fetchRequestStatusJson(requestId: String): String {
        if (requestId.isEmpty()) return "{}"

        return try {
            val snapshot = Tasks.await(
                FirebaseDatabase.getInstance(DATABASE_URL)
                    .getReference(REQUESTS_PATH)
                    .child(requestId)
                    .get(),
                TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )

            if (!snapshot.exists()) return "{}"

            val result = JSONObject()
            result.put("status", snapshot.child("status").getValue(String::class.java) ?: "pending")
            result.put("questionId", snapshot.child("questionId").getValue(String::class.java) ?: "")
            result.put("questionText", snapshot.child("questionText").getValue(String::class.java) ?: "")
            result.put("source", snapshot.child("source").getValue(String::class.java) ?: "")
            result.put("error", snapshot.child("error").getValue(String::class.java) ?: "")
            result.toString()
        } catch (error: Throwable) {
            Log.e(TAG, "Failed reading simulation request id=$requestId", error)
            "{}"
        }
    }

}
