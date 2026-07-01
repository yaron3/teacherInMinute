package teacher.minute

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AndroidImagePickerManager {
    private const val TAG = "AndroidImagePicker"
    private const val PICK_IMAGE_REQUEST = 7104
    private const val CAPTURE_IMAGE_REQUEST = 7105
    private const val TIMEOUT_SECONDS = 300L

    private data class PendingPick(
        val latch: CountDownLatch = CountDownLatch(1),
        @Volatile var resultBase64: String = "",
        @Volatile var error: Throwable? = null
    )

    private val lock = Any()
    private var pendingPick: PendingPick? = null
    @Volatile private var pendingCaptureUri: Uri? = null

    @JvmStatic
    fun pickImageBase64(): String {
        Log.i(TAG, "pickImageBase64 requested")
        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")
        val request = beginPick()

        activity.runOnUiThread {
            try {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                Log.i(TAG, "Starting Android image picker")
                activity.startActivityForResult(
                    Intent.createChooser(intent, "Select image"),
                    PICK_IMAGE_REQUEST
                )
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start Android image picker", error)
                completePending(error = error)
            }
        }

        return awaitResult(request, "pickImageBase64")
    }

    /// Launches the device camera to capture a new photo, returning it as a
    /// base64-encoded JPEG. Complements `pickImageBase64` (gallery) so the user
    /// can either take a picture or choose an existing one.
    @JvmStatic
    fun captureImageBase64(): String {
        Log.i(TAG, "captureImageBase64 requested")
        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")
        val request = beginPick()

        activity.runOnUiThread {
            try {
                val captureFile = File.createTempFile("tim_capture_", ".jpg", activity.cacheDir)
                val captureUri = FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.fileprovider",
                    captureFile
                )
                pendingCaptureUri = captureUri
                val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                    putExtra(MediaStore.EXTRA_OUTPUT, captureUri)
                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                if (intent.resolveActivity(activity.packageManager) == null) {
                    completePending(error = IllegalStateException("No camera is available"))
                    return@runOnUiThread
                }
                Log.i(TAG, "Starting Android camera capture")
                activity.startActivityForResult(intent, CAPTURE_IMAGE_REQUEST)
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start Android camera capture", error)
                completePending(error = error)
            }
        }

        return awaitResult(request, "captureImageBase64")
    }

    private fun beginPick(): PendingPick {
        val request = PendingPick()
        synchronized(lock) {
            if (pendingPick != null) {
                throw IllegalStateException("An image picker is already open")
            }
            pendingPick = request
        }
        return request
    }

    private fun awaitResult(request: PendingPick, label: String): String {
        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for image picker")
        }

        request.error?.let { throw it }
        Log.i(TAG, "$label completed base64Length=${request.resultBase64.length}")
        return request.resultBase64
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val isCapture = requestCode == CAPTURE_IMAGE_REQUEST
        if (requestCode != PICK_IMAGE_REQUEST && !isCapture) {
            return false
        }

        Log.i(TAG, "Image picker resultCode=$resultCode isCapture=$isCapture hasData=${data?.data != null}")

        if (resultCode != Activity.RESULT_OK) {
            Log.i(TAG, "Image picker cancelled")
            pendingCaptureUri = null
            completePending(resultBase64 = "")
            return true
        }

        val activity = MainActivity.currentActivity
        // Camera capture writes to the pre-supplied output URI, so the result
        // intent's data is null; gallery selections carry the URI in the intent.
        val uri = if (isCapture) pendingCaptureUri else data?.data
        pendingCaptureUri = null
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
