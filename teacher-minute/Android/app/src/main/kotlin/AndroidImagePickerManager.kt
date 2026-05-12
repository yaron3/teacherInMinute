package teacher.minute

import android.app.Activity
import android.content.Intent
import android.util.Base64
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AndroidImagePickerManager {
    private const val TAG = "AndroidImagePicker"
    private const val PICK_IMAGE_REQUEST = 7104
    private const val TIMEOUT_SECONDS = 300L

    private data class PendingPick(
        val latch: CountDownLatch = CountDownLatch(1),
        @Volatile var resultBase64: String = "",
        @Volatile var error: Throwable? = null
    )

    private val lock = Any()
    private var pendingPick: PendingPick? = null

    @JvmStatic
    fun pickImageBase64(): String {
        Log.i(TAG, "pickImageBase64 requested")
        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")
        val request = PendingPick()

        synchronized(lock) {
            if (pendingPick != null) {
                throw IllegalStateException("An image picker is already open")
            }
            pendingPick = request
        }

        activity.runOnUiThread {
            try {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                Log.i(TAG, "Starting Android image picker")
                activity.startActivityForResult(
                    Intent.createChooser(intent, "Select verification image"),
                    PICK_IMAGE_REQUEST
                )
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start Android image picker", error)
                completePending(error = error)
            }
        }

        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for image picker")
        }

        request.error?.let { throw it }
        Log.i(TAG, "pickImageBase64 completed base64Length=${request.resultBase64.length}")
        return request.resultBase64
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_IMAGE_REQUEST) {
            return false
        }

        Log.i(TAG, "Image picker resultCode=$resultCode hasData=${data?.data != null}")

        if (resultCode != Activity.RESULT_OK) {
            Log.i(TAG, "Image picker cancelled")
            completePending(resultBase64 = "")
            return true
        }

        val activity = MainActivity.currentActivity
        val uri = data?.data
        if (activity == null || uri == null) {
            Log.e(TAG, "Image picker returned without activity or URI")
            completePending(error = IllegalStateException("No image was selected"))
            return true
        }

        try {
            val bytes = activity.contentResolver.openInputStream(uri)?.use { stream ->
                stream.readBytes()
            } ?: throw IllegalStateException("Could not read selected image")
            completePending(resultBase64 = Base64.encodeToString(bytes, Base64.NO_WRAP))
            Log.i(TAG, "Selected image bytes=${bytes.size}")
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to read selected image", error)
            completePending(error = error)
        }

        return true
    }

    private fun completePending(resultBase64: String = "", error: Throwable? = null) {
        val request = synchronized(lock) {
            val current = pendingPick
            pendingPick = null
            current
        }
        request?.resultBase64 = resultBase64
        request?.error = error
        request?.latch?.countDown()
    }

    private fun clearPending(request: PendingPick) {
        synchronized(lock) {
            if (pendingPick === request) {
                pendingPick = null
            }
        }
    }
}
