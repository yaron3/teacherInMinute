package teacher.minute

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.storage.FirebaseStorage
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

object AndroidBoardImageSaver {
    private const val TAG = "AndroidBoardImageSaver"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"
    private const val UPLOAD_TIMEOUT_SECONDS = 30L
    private const val WRITE_TIMEOUT_SECONDS = 15L

    @JvmStatic
    fun saveBoardSnapshotToChat(
        questionId: String,
        senderRole: String,
        strokesJson: String,
        width: Int,
        height: Int,
        logicalWidth: Double,
        logicalHeight: Double,
        strokeColorArgb: Int,
        backgroundColorArgb: Int,
        saveToChat: Boolean,
        saveToGallery: Boolean
    ): String {
        if (!saveToChat && !saveToGallery) return ""

        val bytes = renderStrokesAsJpeg(
            strokesJson = strokesJson,
            width = width,
            height = height,
            logicalWidth = logicalWidth,
            logicalHeight = logicalHeight,
            strokeColorArgb = strokeColorArgb,
            backgroundColorArgb = backgroundColorArgb
        )
        if (bytes.isEmpty()) {
            Log.w(TAG, "Rendered bytes are empty; aborting save")
            return ""
        }

        val timestamp = System.currentTimeMillis()
        var downloadUrl = ""

        if (saveToChat) {
            downloadUrl = uploadJpegBytes(
                questionId = questionId,
                bytes = bytes,
                timestamp = timestamp
            )
            if (downloadUrl.isNotBlank()) {
                sendImageChatMessage(
                    questionId = questionId,
                    senderRole = senderRole,
                    downloadUrl = downloadUrl,
                    createdAt = timestamp.toDouble()
                )
            }
        }

        if (saveToGallery) {
            saveBytesToGallery(bytes = bytes, filename = "TeacherMinute_$timestamp.jpg")
        }

        return downloadUrl
    }

    private fun renderStrokesAsJpeg(
        strokesJson: String,
        width: Int,
        height: Int,
        logicalWidth: Double,
        logicalHeight: Double,
        strokeColorArgb: Int,
        backgroundColorArgb: Int
    ): ByteArray {
        if (width <= 0 || height <= 0 || logicalWidth <= 0.0 || logicalHeight <= 0.0) {
            return ByteArray(0)
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(backgroundColorArgb)

        val paint = Paint().apply {
            color = strokeColorArgb
            strokeWidth = 3f
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
            isAntiAlias = true
        }

        val scaleX = width.toDouble() / logicalWidth
        val scaleY = height.toDouble() / logicalHeight

        val strokes = try {
            JSONArray(strokesJson)
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to parse strokes JSON", error)
            JSONArray()
        }

        for (i in 0 until strokes.length()) {
            val stroke = strokes.optJSONObject(i) ?: continue
            val points = stroke.optJSONArray("points") ?: continue
            if (points.length() == 0) continue

            val path = Path()
            var moved = false
            for (j in 0 until points.length()) {
                val point = points.optJSONObject(j) ?: continue
                val x = (point.optDouble("x", 0.0) * scaleX).toFloat()
                val y = (point.optDouble("y", 0.0) * scaleY).toFloat()
                if (!moved) {
                    path.moveTo(x, y)
                    moved = true
                } else {
                    path.lineTo(x, y)
                }
            }
            canvas.drawPath(path, paint)
        }

        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output)
        bitmap.recycle()
        return output.toByteArray()
    }

    private fun uploadJpegBytes(
        questionId: String,
        bytes: ByteArray,
        timestamp: Long
    ): String {
        return try {
            val path = "boardSnapshots/$questionId/$timestamp.jpg"
            val ref = FirebaseStorage.getInstance().reference.child(path)
            Tasks.await(
                ref.putBytes(bytes),
                UPLOAD_TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )
            val url = Tasks.await(
                ref.downloadUrl,
                WRITE_TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )
            url.toString()
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to upload board snapshot", error)
            ""
        }
    }

    private fun sendImageChatMessage(
        questionId: String,
        senderRole: String,
        downloadUrl: String,
        createdAt: Double
    ) {
        try {
            val uid = FirebaseAuth.getInstance().currentUser?.uid
                ?: throw IllegalStateException("Not signed in")
            val ref = FirebaseDatabase.getInstance(DATABASE_URL)
                .getReference("questions")
                .child(questionId)
                .child("messages")
                .push()
            val payload = mapOf(
                "text" to downloadUrl,
                "senderUid" to uid,
                "senderRole" to senderRole,
                "createdAt" to createdAt,
                "kind" to "image"
            )
            Tasks.await(
                ref.setValue(payload),
                WRITE_TIMEOUT_SECONDS,
                TimeUnit.SECONDS
            )
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to send image chat message", error)
        }
    }

    private fun saveBytesToGallery(bytes: ByteArray, filename: String): Boolean {
        val activity = MainActivity.currentActivity ?: return false
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/TeacherMinute")
                }
            }
            val resolver = activity.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: return false
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
            } ?: return false
            true
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to save board snapshot to gallery", error)
            false
        }
    }
}
