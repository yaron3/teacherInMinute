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
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val AVAILABILITY_TIMEOUT_SECONDS = 5L

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
                FirebaseDatabase.getInstance(DATABASE_URL)
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
     * Reads the projection rather than `teachers`, which is owner-only because
     * it also holds student names under waitingMessages — reading it here fails
     * with "Permission denied".
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
                FirebaseDatabase.getInstance(DATABASE_URL)
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
        val baseValues = mutableMapOf<String, Any>(
            "status" to status,
            "isOnline" to (status == "online"),
            "updatedAt" to ServerValue.TIMESTAMP
        )

        if (status != "online") {
            updateTeacherRecord(uid, status, baseValues)
            return
        }

        FirebaseFirestore.getInstance()
            .collection("users")
            .document(uid)
            .get()
            .addOnSuccessListener { document ->
                val subjectSelections = document.get("subjectSelections")
                val subjects = normalizedSubjects(subjectSelections)

                if (subjects.isEmpty()) {
                    Log.w(TAG, "Teacher has no RTDB-matchable subjects uid=$uid")
                }

                val values = baseValues.toMutableMap()
                values["uid"] = uid
                values["displayName"] = document.getString("fullName") ?: "Teacher"
                values["subjects"] = subjects
                values["ratingAvg"] = document.getDouble("ratingAvg") ?: 5.0
                values["acceptRate"] = document.getDouble("acceptRate") ?: 1.0
                values["lastActiveAt"] = System.currentTimeMillis()

                updateTeacherRecord(uid, status, values)
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed loading Firestore profile for teacher uid=$uid", error)
                baseValues["lastActiveAt"] = System.currentTimeMillis()
                updateTeacherRecord(uid, status, baseValues)
            }
    }

    private fun updateTeacherRecord(uid: String, status: String, values: Map<String, Any>) {
        val teacherRef = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("teachers")
            .child(uid)

        if (status == "online") {
            teacherRef.onDisconnect().updateChildren(
                mapOf(
                    "status" to "offline",
                    "isOnline" to false,
                    "updatedAt" to ServerValue.TIMESTAMP
                )
            )
        } else {
            teacherRef.onDisconnect().cancel()
        }

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
