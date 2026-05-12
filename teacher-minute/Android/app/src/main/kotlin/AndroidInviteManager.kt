package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.database.FirebaseDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object AndroidInviteManager {
    private const val TAG = "AndroidInviteManager"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val TIMEOUT_SECONDS = 15L

    @JvmStatic
    fun fetchInvitesJson(teacherUid: String): String {
        Log.i(TAG, "Fetching invites uid=$teacherUid")

        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("teacherInvites")
                .child(teacherUid)
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )

        Log.i(TAG, "Invite snapshot exists=${snapshot.exists()} children=${snapshot.childrenCount} uid=$teacherUid")

        val invites = mutableListOf<JSONObject>()

        for (child in snapshot.children) {
            val id = child.key
            if (id == null) {
                Log.w(TAG, "Skipping invite with missing key")
                continue
            }

            val topic = child.child("topic").getValue(String::class.java)
                ?: child.child("subject").getValue(String::class.java)
            val text = child.child("text").getValue(String::class.java)
                ?: child.child("questionText").getValue(String::class.java)
                ?: child.child("question").getValue(String::class.java)
            val expiresAt = child.child("expiresAt").value.asDoubleOrNull()
                ?: (System.currentTimeMillis() + 12_000).toDouble()
            val wave = child.child("wave").value.asIntOrNull() ?: 1

            if (topic == null || text == null) {
                Log.w(
                    TAG,
                    "Skipping invite id=$id missingFields topic=${topic != null} text=${text != null}"
                )
                continue
            }

            Log.i(
                TAG,
                "Loaded invite id=$id topic=$topic wave=$wave secondsRemaining=${(expiresAt - System.currentTimeMillis()) / 1000.0}"
            )

            invites.add(
                JSONObject()
                    .put("id", id)
                    .put("topic", topic)
                    .put("text", text)
                    .put("expiresAt", expiresAt)
                    .put("wave", wave)
            )
        }

        val array = JSONArray()
        invites.sortedBy { it.optDouble("expiresAt") }.forEach { array.put(it) }
        Log.i(TAG, "Fetched invites count=${array.length()} uid=$teacherUid")
        return array.toString()
    }

    private fun Any?.asDoubleOrNull(): Double? {
        return when (this) {
            is Number -> toDouble()
            is String -> toDoubleOrNull()
            else -> null
        }
    }

    private fun Any?.asIntOrNull(): Int? {
        return when (this) {
            is Number -> toInt()
            is String -> toIntOrNull()
            else -> null
        }
    }
}
