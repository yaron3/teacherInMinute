package teacher.minute

import android.app.Activity
import android.content.Intent
import android.util.Log
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AndroidGoogleSignInManager {
    private const val TAG = "AndroidGoogleSignIn"
    private const val RC_SIGN_IN = 9001
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
                throw IllegalStateException("Google sign-in is already active")
            }
            pendingSignIn = request
        }

        activity.runOnUiThread {
            try {
                val webClientId = webClientId(activity)
                if (webClientId.isBlank()) {
                    completePending(error = IllegalStateException("Missing Android Google web client ID"))
                    return@runOnUiThread
                }

                val client = googleSignInClient(activity, webClientId)
                Log.i(TAG, "Starting Google sign-in")
                activity.startActivityForResult(client.signInIntent, RC_SIGN_IN)
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start Google sign-in", error)
                completePending(error = error)
            }
        }

        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for Google sign-in")
        }

        request.error?.let { throw it }
        return request.result
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != RC_SIGN_IN) {
            return false
        }

        Log.i(TAG, "Google sign-in resultCode=$resultCode hasData=${data != null}")
        if (resultCode != Activity.RESULT_OK) {
            completePending(error = IllegalStateException("Google sign-in was cancelled"))
            return true
        }

        val task = GoogleSignIn.getSignedInAccountFromIntent(data)
        try {
            val account = task.getResult(ApiException::class.java)
            val idToken = account.idToken
            if (idToken.isNullOrBlank()) {
                completePending(error = IllegalStateException("Google ID token was empty"))
                return true
            }

            val credential = GoogleAuthProvider.getCredential(idToken, null)
            FirebaseAuth.getInstance().signInWithCredential(credential)
                .addOnCompleteListener { firebaseTask ->
                    if (firebaseTask.isSuccessful) {
                        val user = firebaseTask.result?.user
                        completePending(result = listOf(
                            "success",
                            user?.uid.orEmpty(),
                            user?.email.orEmpty()
                        ).joinToString("|"))
                    } else {
                        completePending(
                            error = firebaseTask.exception ?: IllegalStateException("Firebase Google sign-in failed")
                        )
                    }
                }
        } catch (error: ApiException) {
            completePending(error = error)
        }

        return true
    }

    private fun googleSignInClient(activity: Activity, webClientId: String): GoogleSignInClient {
        val options = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestIdToken(webClientId)
            .requestEmail()
            .build()
        return GoogleSignIn.getClient(activity, options)
    }

    private fun webClientId(activity: Activity): String {
        val resourceId = activity.resources.getIdentifier(
            "default_web_client_id",
            "string",
            activity.packageName
        )
        if (resourceId != 0) {
            return activity.getString(resourceId)
        }

        return ""
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
