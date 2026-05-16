package teacher.minute

import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.OAuthProvider
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AndroidAppleSignInManager {
    private const val TAG = "AndroidAppleSignIn"
    private const val TIMEOUT_SECONDS = 300L

    private data class PendingSignIn(
        val latch: CountDownLatch = CountDownLatch(1),
        @Volatile var result: String = "",
        @Volatile var error: Throwable? = null
    )

    private val lock = Any()
    private var pendingSignIn: PendingSignIn? = null

    @JvmStatic
    fun signIn(): String {
        Log.i(TAG, "signIn requested")
        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")
        val request = PendingSignIn()

        synchronized(lock) {
            if (pendingSignIn != null) {
                throw IllegalStateException("Apple sign-in is already active")
            }
            pendingSignIn = request
        }

        activity.runOnUiThread {
            try {
                val provider = OAuthProvider.newBuilder("apple.com")
                    .addCustomParameter("locale", "en")
                    .setScopes(listOf("email", "name"))
                    .build()

                val auth = FirebaseAuth.getInstance()
                val pendingResultTask = auth.pendingAuthResult
                val task = pendingResultTask ?: auth.startActivityForSignInWithProvider(activity, provider)

                task.addOnSuccessListener { result ->
                    val user = result.user
                    completePending(
                        result = listOf(
                            "success",
                            user?.uid.orEmpty(),
                            user?.email.orEmpty()
                        ).joinToString("|")
                    )
                }.addOnFailureListener { error ->
                    Log.e(TAG, "Apple sign-in failed", error)
                    completePending(error = error)
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start Apple sign-in", error)
                completePending(error = error)
            }
        }

        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for Apple sign-in")
        }

        request.error?.let { throw it }
        return request.result
    }

    private fun completePending(result: String = "", error: Throwable? = null) {
        val request = synchronized(lock) {
            val current = pendingSignIn
            pendingSignIn = null
            current
        }
        request?.result = result
        request?.error = error
        request?.latch?.countDown()
    }

    private fun clearPending(request: PendingSignIn) {
        synchronized(lock) {
            if (pendingSignIn === request) {
                pendingSignIn = null
            }
        }
    }
}
