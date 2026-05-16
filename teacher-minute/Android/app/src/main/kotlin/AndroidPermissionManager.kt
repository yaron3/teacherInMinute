package teacher.minute

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AndroidPermissionManager {
    private const val TAG = "AndroidPermission"
    private const val REQUEST_PERMISSION = 7205
    private const val TIMEOUT_SECONDS = 120L

    private data class PendingRequest(
        val permission: String,
        val latch: CountDownLatch = CountDownLatch(1),
        @Volatile var granted: Boolean = false
    )

    private val lock = Any()
    private var pendingRequest: PendingRequest? = null

    @JvmStatic
    fun hasPermission(permission: String): Boolean {
        if (permission == Manifest.permission.POST_NOTIFICATIONS && Build.VERSION.SDK_INT < 33) {
            return true
        }
        val activity = MainActivity.currentActivity ?: return false
        return ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
    }

    @JvmStatic
    fun requestPermission(permission: String): Boolean {
        if (hasPermission(permission)) {
            return true
        }

        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")
        val request = PendingRequest(permission)

        synchronized(lock) {
            if (pendingRequest != null) {
                throw IllegalStateException("A permission request is already active")
            }
            pendingRequest = request
        }

        activity.runOnUiThread {
            Log.i(TAG, "Requesting permission=$permission")
            ActivityCompat.requestPermissions(activity, arrayOf(permission), REQUEST_PERMISSION)
        }

        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for permission response")
        }

        return request.granted
    }

    fun handleRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_PERMISSION) {
            return false
        }

        val request = synchronized(lock) {
            val current = pendingRequest
            pendingRequest = null
            current
        } ?: return true

        val index = permissions.indexOf(request.permission)
        request.granted = index >= 0 && grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
        request.latch.countDown()
        Log.i(TAG, "Permission result permission=${request.permission} granted=${request.granted}")
        return true
    }

    private fun clearPending(request: PendingRequest) {
        synchronized(lock) {
            if (pendingRequest === request) {
                pendingRequest = null
            }
        }
    }
}
