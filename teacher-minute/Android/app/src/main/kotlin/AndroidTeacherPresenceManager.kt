package teacher.minute

import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.firestore.FirebaseFirestore

object AndroidTeacherPresenceManager {
    private const val TAG = "TeacherPresence"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"

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
        FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("teachers")
            .child(uid)
            .updateChildren(values)
            .addOnSuccessListener {
                Log.i(TAG, "Wrote teacher status=$status uid=$uid keys=${values.keys}")
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed writing teacher status=$status uid=$uid", error)
            }
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
