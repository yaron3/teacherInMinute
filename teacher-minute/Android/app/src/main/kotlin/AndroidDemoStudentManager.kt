package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.database.FirebaseDatabase
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Android side of the "simulate an incoming student question" demo tool.
 *
 * The teacher app writes one request node under `demoStudent/requests`; the
 * local `backend/demo-student` service picks it up, writes the question with a
 * local AI model, and updates the same node with the outcome.
 */
object AndroidDemoStudentManager {
    private const val TAG = "AndroidDemoStudent"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val TIMEOUT_SECONDS = 15L
    private const val REQUESTS_PATH = "demoStudent/requests"

    /** Writes one simulation request. Returns the request id, or "" on failure. */
    @JvmStatic
    fun submitRequestJson(json: String): String {
        val payload = try {
            toMap(JSONObject(json))
        } catch (error: Throwable) {
            Log.e(TAG, "Invalid simulation payload", error)
            return ""
        }

        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference(REQUESTS_PATH)
            .push()

        return try {
            Tasks.await(ref.setValue(payload), TIMEOUT_SECONDS, TimeUnit.SECONDS)
            val requestId = ref.key ?: ""
            Log.i(TAG, "Submitted simulation request id=$requestId")
            requestId
        } catch (error: Throwable) {
            Log.e(TAG, "Failed submitting simulation request", error)
            ""
        }
    }

    /** Reads the local service's presence: "online", "offline", or "" when unknown. */
    @JvmStatic
    fun fetchServiceStatus(): String {
        return try {
            val snapshot = Tasks.await(
                FirebaseDatabase.getInstance(DATABASE_URL)
                    .getReference("demoStudent/service/status")
                    .get(),
                TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )
            snapshot.getValue(String::class.java) ?: ""
        } catch (error: Throwable) {
            Log.e(TAG, "Failed reading demo student service status", error)
            ""
        }
    }

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

    private fun toMap(json: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        for (key in json.keys()) {
            when (val value = json.get(key)) {
                is Int -> map[key] = value.toDouble()
                is Long -> map[key] = value.toDouble()
                is Double -> map[key] = value
                is Boolean -> map[key] = value
                JSONObject.NULL -> Unit
                else -> map[key] = value.toString()
            }
        }
        return map
    }
}
