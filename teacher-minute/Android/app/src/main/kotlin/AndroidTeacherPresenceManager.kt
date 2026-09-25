package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.firestore.FirebaseFirestore
import java.util.concurrent.TimeUnit

object AndroidTeacherPresenceManager {
    private const val TAG = "TeacherPresence"
    private const val AVAILABILITY_TIMEOUT_SECONDS = 5L

    /** The status most recently asked of setTeacherStatus. Going online waits
     *  on a profile read before it writes, so a toggle turned off meanwhile
     *  must stop that write from landing after the offline one. */
    @Volatile
    private var requestedStatus: String? = null

    /**
     * Whether any teacher is online, from the public `onlineTeachers`
     * projection. Every entry there is online by construction, so the presence
     * of any child is the answer.
     *
     * Previously read `teachers`, which is owner-only — the read always failed
     * and the catch below answered "available" regardless of reality.
     */
    @JvmStatic
    fun hasOnlineTeacher(): Boolean {
        return try {
            val snapshot = Tasks.await(
                FirebaseDatabase.getInstance()
                    .getReference("onlineTeachers")
                    .get(),
                AVAILABILITY_TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )
            val hasAny = snapshot.childrenCount > 0
            Log.i(TAG, "hasOnlineTeacher=$hasAny count=${snapshot.childrenCount}")
            hasAny
        } catch (error: Throwable) {
            // Still optimistic: blocking a student from asking because a
            // presence read failed is worse than dispatching to nobody.
            Log.e(TAG, "hasOnlineTeacher check failed; assuming available", error)
            true
        }
    }

    /**
     * The teachers currently online, from the public `onlineTeachers`
     * projection the backend maintains (functions/src/presence.ts). Returned as
     * a JSON array of `{"id", "subjects", "displayName", "photoUrl"}`, the shape
     * OnlineTeachersStore decodes on the Swift side.
     *
     * Reads the projection rather than `teachers`, which the database rules
     * keep owner-only — reading another teacher's node here fails with
     * "Permission denied".
     *
     * JSON rather than a bridged object graph because the JNI bridge carries
     * strings cheaply, and this is read once per load rather than continuously.
     * Returns "[]" on failure: an empty grid is a better outcome than blocking
     * the home screen on a presence read.
     */
    @JvmStatic
    fun onlineTeachersJSON(): String {
        return try {
            val snapshot = Tasks.await(
                FirebaseDatabase.getInstance()
                    .getReference("onlineTeachers")
                    .get(),
                AVAILABILITY_TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )
            val teachers = org.json.JSONArray()
            for (child in snapshot.children) {
                val uid = child.key ?: continue
                val entry = org.json.JSONObject()
                entry.put("id", uid)
                entry.put("subjects", org.json.JSONArray(stringList(child.child("subjects").value)))
                entry.put("displayName", child.child("displayName").getValue(String::class.java) ?: "")
                entry.put("photoUrl", child.child("photoUrl").getValue(String::class.java) ?: "")
                entry.put("busy", child.child("busy").getValue(Boolean::class.java) ?: false)
                teachers.put(entry)
            }
            Log.i(TAG, "onlineTeachersJSON count=${teachers.length()}")
            teachers.toString()
        } catch (error: Throwable) {
            Log.e(TAG, "onlineTeachersJSON failed", error)
            "[]"
        }
    }

    @JvmStatic
    fun setCurrentTeacherStatus(status: String) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid == null) {
            Log.w(TAG, "setCurrentTeacherStatus skipped: no current user")
            return
        }

        setTeacherStatus(uid, status)
    }

    @JvmStatic
    fun setTeacherStatus(uid: String, status: String) {
        requestedStatus = status
        val baseValues = mutableMapOf<String, Any>(
            // What the teacher asked for, as opposed to whether they are in the
            // dispatch pool. Only this path writes it. The backend writes
            // `status` too — it takes offline a teacher whose app stopped
            // sending keep-alives and who has no push token (see
            // functions/src/keepAlive.ts) — but leaves this alone, so a toggle
            // left on still reads "available", and a toggle turned off "dnd".
            "availability" to if (status == "online") "available" else "dnd",
            "status" to status,
            "isOnline" to (status == "online"),
            "updatedAt" to ServerValue.TIMESTAMP
        )

        if (status != "online") {
            updateTeacherRecord(uid, status, baseValues)
            return
        }

        // In the same update as the status, so the backend never sees this
        // teacher online beside a keep-alive left over from an earlier session.
        baseValues["lastSeenAt"] = ServerValue.TIMESTAMP

        FirebaseFirestore.getInstance()
            .collection("users")
            .document(uid)
            .get()
            .addOnSuccessListener { document ->
                if (requestedStatus != "online") {
                    Log.i(TAG, "Skipped a stale online write uid=$uid; went offline meanwhile")
                    return@addOnSuccessListener
                }
                val subjectSelections = document.get("subjectSelections")
                val subjects = normalizedSubjects(subjectSelections)

                if (subjects.isEmpty()) {
                    Log.w(TAG, "Teacher has no RTDB-matchable subjects uid=$uid")
                }

                val values = baseValues.toMutableMap()
                values["uid"] = uid
                values["displayName"] = document.getString("fullName") ?: "Teacher"
                values["subjects"] = subjects
                // Deliberately not writing ratingAvg or acceptRate. Ranking is
                // decided on those, so the app being ranked cannot be the one
                // supplying them — this used to default to five stars for
                // everybody. The backend stamps the earned rating when
                // presence is published, and again whenever a student rates.
                values["lastActiveAt"] = System.currentTimeMillis()

                updateTeacherRecord(uid, status, values)
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed loading Firestore profile for teacher uid=$uid", error)
                if (requestedStatus != "online") {
                    Log.i(TAG, "Skipped a stale online write uid=$uid; went offline meanwhile")
                    return@addOnFailureListener
                }
                baseValues["lastActiveAt"] = System.currentTimeMillis()
                updateTeacherRecord(uid, status, baseValues)
            }
    }

    /**
     * Tells the backend the app is still running — see TeacherKeepAlive.swift.
     *
     * Re-sends `status: "online"` with the timestamp, so a teacher the backend
     * took offline while the app was away is back in the pool as soon as it
     * runs again. The timestamp must be the server's: the database rules refuse
     * any other.
     *
     * Takes the uid instead of reading the signed-in user, so a keep-alive
     * still on its way when one account signs out cannot land on the next.
     */
    @JvmStatic
    fun sendKeepAlive(uid: String) {
        if (FirebaseAuth.getInstance().currentUser?.uid != uid) {
            Log.w(TAG, "sendKeepAlive skipped: uid=$uid is not the signed-in user")
            return
        }
        // Only ever repeats an "online". A keep-alive must not undo a teacher
        // going offline, whoever asked for it.
        if (requestedStatus != "online") {
            Log.w(TAG, "sendKeepAlive skipped: last status asked for is $requestedStatus")
            return
        }
        FirebaseDatabase.getInstance()
            .getReference("teachers")
            .child(uid)
            .updateChildren(
                mapOf<String, Any>(
                    "status" to "online",
                    "isOnline" to true,
                    "lastSeenAt" to ServerValue.TIMESTAMP
                )
            )
            .addOnFailureListener { error ->
                Log.e(TAG, "Keep-alive write failed uid=$uid", error)
            }
    }

    // No onDisconnect handler: it set `status` offline whenever the socket
    // closed, with no regard for whether a push could still reach the teacher.
    // The backend decides that from the keep-alive instead.
    private fun updateTeacherRecord(uid: String, status: String, values: Map<String, Any>) {
        val teacherRef = FirebaseDatabase.getInstance()
            .getReference("teachers")
            .child(uid)

        teacherRef
            .updateChildren(values)
            .addOnSuccessListener {
                Log.i(TAG, "Wrote teacher status=$status uid=$uid keys=${values.keys}")
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed writing teacher status=$status uid=$uid", error)
            }
    }

    /** Subjects in the projection are already normalized by the writer, so
     *  they are read verbatim — re-running them through `normalizedSubjects`
     *  would silently drop every subject outside its math-only whitelist. */
    private fun stringList(raw: Any?): List<String> = when (raw) {
        is List<*> -> raw.mapNotNull { it as? String }
        is String -> listOf(raw)
        else -> emptyList()
    }

    private fun normalizedSubjects(raw: Any?): List<String> {
        val titles = mutableListOf<String>()

        when (raw) {
            is Map<*, *> -> {
                for (value in raw.values) {
                    when (value) {
                        is List<*> -> value.forEach { if (it is String) titles.add(it) }
                        is Array<*> -> value.forEach { if (it is String) titles.add(it) }
                        is String -> titles.add(value)
                    }
                }
            }
            is List<*> -> raw.forEach { if (it is String) titles.add(it) }
        }

        return titles
            .mapNotNull { title ->
                when (title.trim().lowercase()) {
                    "algebra", "algebra ii" -> "algebra"
                    "geometry" -> "geometry"
                    "trigonometry" -> "trigonometry"
                    "calculus" -> "calculus"
                    "statistics" -> "statistics"
                    "arithmetic", "general math", "math" -> "arithmetic"
                    else -> null
                }
            }
            .distinct()
    }
}
