package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object AndroidInviteManager {
    private const val TAG = "AndroidInviteManager"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val TIMEOUT_SECONDS = 15L

    // A question reaching an Android teacher used to mean waiting for the next
    // 2s poll and then a full round trip to RTDB — over a second of delay, on
    // top of everything the backend spends getting the invite written. This
    // listener keeps the answer in memory instead, so the Swift side's poll is
    // a local read and can run often enough to be invisible.
    @Volatile private var cachedInvitesJson: String? = null
    @Volatile private var liveError: String? = null
    private var listener: ValueEventListener? = null
    private var listenerRef: DatabaseReference? = null
    private var listenerTeacherId: String? = null

    @JvmStatic
    @Synchronized
    fun startListening(teacherId: String) {
        if (listenerTeacherId == teacherId && listener != null) return
        stopListening()

        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("teacherInvites")
            .child(teacherId)

        val valueListener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                cachedInvitesJson = encodeInvites(snapshot, teacherId)
                liveError = null
            }

            override fun onCancelled(error: DatabaseError) {
                Log.e(TAG, "Invite listener cancelled uid=$teacherId", error.toException())
                liveError = error.message
            }
        }

        ref.addValueEventListener(valueListener)
        listener = valueListener
        listenerRef = ref
        listenerTeacherId = teacherId
        Log.i(TAG, "Invite listener attached uid=$teacherId")
    }

    @JvmStatic
    @Synchronized
    fun stopListening() {
        val currentListener = listener
        val currentRef = listenerRef
        if (currentListener != null && currentRef != null) {
            currentRef.removeEventListener(currentListener)
            Log.i(TAG, "Invite listener detached uid=$listenerTeacherId")
        }
        listener = null
        listenerRef = null
        listenerTeacherId = null
        cachedInvitesJson = null
        liveError = null
    }

    /**
     * The listener's latest view, as `{"state": ..., "invites": [...]}`.
     *
     * `state` is "ready" once a snapshot has arrived, "error" if the listener
     * was cancelled, and "pending" before the first delivery — the caller falls
     * back to a one-shot [fetchInvitesJson] on anything but "ready", so a
     * listener that never attaches degrades to the old behaviour rather than
     * leaving a teacher with no questions.
     */
    @JvmStatic
    fun liveInvitesJson(): String {
        val invites = cachedInvitesJson
        val error = liveError
        val state = when {
            error != null -> "error"
            invites != null -> "ready"
            else -> "pending"
        }
        return JSONObject()
            .put("state", state)
            .put("invites", JSONArray(invites ?: "[]"))
            .toString()
    }

    @JvmStatic
    fun fetchInvitesJson(teacherId: String): String {
        Log.i(TAG, "Fetching invites uid=$teacherId")

        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("teacherInvites")
                .child(teacherId)
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )

        return encodeInvites(snapshot, teacherId)
    }

    private fun encodeInvites(snapshot: DataSnapshot, teacherId: String): String {
        Log.i(TAG, "Invite snapshot exists=${snapshot.exists()} children=${snapshot.childrenCount} uid=$teacherId")

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
            val photoUrls = JSONArray()
            for (photo in child.child("photoUrls").children) {
                val url = photo.getValue(String::class.java)
                if (!url.isNullOrBlank()) photoUrls.put(url)
            }
            val hasVoiceMessage =
                !child.child("voiceMessageUrl").getValue(String::class.java).isNullOrBlank() ||
                    !child.child("audioUrl").getValue(String::class.java).isNullOrBlank() ||
                    !child.child("voiceUrl").getValue(String::class.java).isNullOrBlank()
            val studentName = child.firstString("studentName", "studentFullName", "studentDisplayName", "name")
            val studentImageURL = child.firstString("studentImageURL", "studentImageUrl", "studentPhotoUrl", "studentPhotoURL")
            val studentId = child.firstString("studentId", "studentUID", "studentId")
            val pricePerMinuteCents = child.child("pricePerMinuteCents").value.asIntOrNull()
                ?: child.child("ratePerMinuteCents").value.asIntOrNull()
                ?: child.child("costPerMinuteCents").value.asIntOrNull()
                ?: 50
            val conversationType = child.child("conversationType").getValue(String::class.java) ?: "text"

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
                    .put("photoUrls", photoUrls)
                    .put("hasVoiceMessage", hasVoiceMessage)
                    .put("studentId", studentId)
                    .put("studentName", studentName)
                    .put("studentImageURL", studentImageURL)
                    .put("pricePerMinuteCents", pricePerMinuteCents)
                    .put("conversationType", conversationType)
            )
        }

        val array = JSONArray()
        invites.sortedBy { it.optDouble("expiresAt") }.forEach { array.put(it) }
        Log.i(TAG, "Fetched invites count=${array.length()} uid=$teacherId")
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

    private fun com.google.firebase.database.DataSnapshot.firstString(vararg keys: String): String {
        for (key in keys) {
            val value = child(key).getValue(String::class.java)
            if (!value.isNullOrBlank()) return value
        }
        return ""
    }
}
