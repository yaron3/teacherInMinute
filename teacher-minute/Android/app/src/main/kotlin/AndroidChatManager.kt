package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object AndroidChatManager {
    private const val TAG = "AndroidChatManager"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val TIMEOUT_SECONDS = 15L

    @JvmStatic
    fun fetchMessagesJson(questionId: String): String {
        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("questions")
                .child(questionId)
                .child("messages")
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )

        val array = JSONArray()
        for (child in snapshot.children) {
            val id = child.key ?: continue
            val text = child.child("text").getValue(String::class.java) ?: continue
            val senderUid = child.child("senderUid").getValue(String::class.java) ?: continue
            val senderRole = child.child("senderRole").getValue(String::class.java) ?: "student"
            val createdAt = child.child("createdAt").value.asDoubleOrNull() ?: 0.0

            array.put(
                JSONObject()
                    .put("id", id)
                    .put("text", text)
                    .put("senderUid", senderUid)
                    .put("senderRole", senderRole)
                    .put("createdAt", createdAt)
            )
        }
        Log.i(TAG, "Fetched board strokes questionId=$questionId count=${array.length()}")
        return array.toString()
    }

    @JvmStatic
    fun sendText(questionId: String, text: String, senderRole: String) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid
            ?: throw IllegalStateException("Not signed in")
        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("questions")
            .child(questionId)
            .child("messages")
            .push()

        val payload = mapOf(
            "text" to text,
            "senderUid" to uid,
            "senderRole" to senderRole,
            "createdAt" to System.currentTimeMillis().toDouble(),
            "kind" to "text"
        )

        Log.i(TAG, "Sending message questionId=$questionId role=$senderRole")
        Tasks.await(ref.setValue(payload), TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    @JvmStatic
    fun fetchBoardStrokesJson(questionId: String): String {
        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("questions")
                .child(questionId)
                .child("board")
                .child("strokes")
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )

        val array = JSONArray()
        for (child in snapshot.children) {
            val id = child.key ?: continue
            val points = JSONArray()
            for (point in child.child("points").children) {
                val x = point.child("x").value.asDoubleOrNull() ?: continue
                val y = point.child("y").value.asDoubleOrNull() ?: continue
                points.put(JSONObject().put("x", x).put("y", y))
            }
            if (points.length() == 0) continue

            array.put(
                JSONObject()
                    .put("id", id)
                    .put("points", points)
                    .put("createdAt", child.child("createdAt").value.asDoubleOrNull() ?: 0.0)
                    .put("senderUid", child.child("senderUid").getValue(String::class.java) ?: "")
            )
        }
        return array.toString()
    }

    @JvmStatic
    fun sendStroke(questionId: String, pointsJson: String) {
        val pointsArray = JSONArray(pointsJson)
        val points = mutableListOf<Map<String, Double>>()
        for (index in 0 until pointsArray.length()) {
            val point = pointsArray.optJSONObject(index) ?: continue
            points.add(
                mapOf(
                    "x" to point.optDouble("x", 0.0),
                    "y" to point.optDouble("y", 0.0)
                )
            )
        }
        if (points.isEmpty()) return

        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("questions")
            .child(questionId)
            .child("board")
            .child("strokes")
            .push()

        val uid = FirebaseAuth.getInstance().currentUser?.uid
            ?: throw IllegalStateException("Not signed in")
        val payload = mapOf(
            "points" to points,
            "createdAt" to System.currentTimeMillis().toDouble(),
            "senderUid" to uid
        )

        Log.i(TAG, "Sending board stroke questionId=$questionId points=${points.size}")
        Tasks.await(ref.setValue(payload), TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    @JvmStatic
    fun clearBoard(questionId: String) {
        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("questions")
            .child(questionId)
            .child("board")
            .child("strokes")
        Tasks.await(ref.removeValue(), TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    @JvmStatic
    fun fetchBoardViewportsJson(questionId: String): String {
        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("questions")
                .child(questionId)
                .child("board")
                .child("viewports")
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )

        val rows = JSONObject()
        for (child in snapshot.children) {
            val key = child.key ?: continue
            val width = child.child("width").value.asDoubleOrNull() ?: continue
            val height = child.child("height").value.asDoubleOrNull() ?: continue
            if (width <= 0.0 || height <= 0.0) continue
            rows.put(
                key,
                JSONObject()
                    .put("x", child.child("x").value.asDoubleOrNull() ?: 0.0)
                    .put("y", child.child("y").value.asDoubleOrNull() ?: 0.0)
                    .put("width", width)
                    .put("height", height)
                    .put("updatedAt", child.child("updatedAt").value.asDoubleOrNull() ?: 0.0)
            )
        }
        return rows.toString()
    }

    @JvmStatic
    fun updateBoardViewport(
        questionId: String,
        role: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        if (width <= 0.0 || height <= 0.0) return
        val key = role.trim().lowercase().ifBlank { "participant" }
        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("questions")
            .child(questionId)
            .child("board")
            .child("viewports")
            .child(key)
        val payload = mapOf(
            "x" to x,
            "y" to y,
            "width" to width,
            "height" to height,
            "updatedAt" to System.currentTimeMillis().toDouble()
        )
        Tasks.await(ref.setValue(payload), TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    @JvmStatic
    fun markQuestionAccepted(questionId: String, teacherId: String) {
        val values = mutableMapOf<String, Any>(
            "status" to "accepted",
            "acceptedAt" to System.currentTimeMillis().toDouble()
        )
        if (teacherId.isNotBlank()) {
            values["teacherId"] = teacherId
        }

        Log.i(TAG, "Marking question accepted questionId=$questionId teacherId=$teacherId")
        val ref = FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("questions")
            .child(questionId)
        Tasks.await(ref.updateChildren(values), TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    @JvmStatic
    fun fetchQuestionStatusJson(questionId: String): String {
        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("questions")
                .child(questionId)
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )

        val status = snapshot.child("status").getValue(String::class.java)
        if (status.isNullOrBlank()) {
            return JSONObject().toString()
        }

        return JSONObject()
            .put("status", status)
            .put("liveKitRoom", snapshot.child("liveKitRoom").getValue(String::class.java) ?: "")
            .put("liveKitToken", snapshot.child("liveKitToken").getValue(String::class.java) ?: "")
            .put("questionId", snapshot.firstString("questionId", "questionID", "id"))
            .toString()
    }

    @JvmStatic
    fun fetchSessionDetailsJson(questionId: String): String {
        val snapshot = Tasks.await(
            FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("questions")
                .child(questionId)
                .get(),
            TIMEOUT_SECONDS,
            TimeUnit.SECONDS
        )
        if (!snapshot.exists()) return JSONObject().toString()

        return JSONObject()
            .put("questionId", snapshot.firstString("questionId", "questionID", "id"))
            .put("studentId", snapshot.firstString("studentId", "studentUID", "studentId"))
            .put("teacherId", snapshot.firstString("teacherId", "teacherUID", "teacherId"))
            .put("studentName", snapshot.firstString("studentName", "studentFullName", "studentDisplayName", "name"))
            .put("teacherName", snapshot.firstString("teacherName", "teacherFullName", "teacherDisplayName"))
            .put("text", snapshot.firstString("text", "questionText", "originalQuestion", "message", "topic"))
            .put("createdAt", snapshot.child("createdAt").value.asDoubleOrNull() ?: 0.0)
            .put(
                "acceptedAt",
                snapshot.child("acceptedAt").value.asDoubleOrNull()
                    ?: snapshot.child("connectedAt").value.asDoubleOrNull()
                    ?: snapshot.child("startedAt").value.asDoubleOrNull()
                    ?: 0.0
            )
            .put(
                "connectionFeeCents",
                snapshot.child("connectionFeeCents").value.asIntOrNull()
                    ?: snapshot.child("connectionFee").value.asIntOrNull()
                    ?: 0
            )
            .put(
                "pricePerMinuteCents",
                snapshot.child("pricePerMinuteCents").value.asIntOrNull()
                    ?: snapshot.child("ratePerMinuteCents").value.asIntOrNull()
                    ?: snapshot.child("costPerMinuteCents").value.asIntOrNull()
                    ?: 0
            )
            .put(
                "teacherSharePercent",
                snapshot.child("teacherSharePercent").value.asDoubleOrNull()
                    ?: snapshot.child("teacherShare").value.asDoubleOrNull()
                    ?: 75.0
            )
            .toString()
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
