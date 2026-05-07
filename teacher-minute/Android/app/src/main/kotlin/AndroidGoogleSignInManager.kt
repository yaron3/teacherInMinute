//
//  AndroidGoogleSignInManager.kt
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//


import android.app.Activity
import android.content.Context
import android.content.Intent

import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider

data class FirebaseSignInResult(
    val isSuccess: Boolean,
    val userId: String? = null,
    val email: String? = null,
    val errorMessage: String? = null
) {
    companion object {
        fun success(userId: String?, email: String?) = FirebaseSignInResult(
            isSuccess = true,
            userId = userId,
            email = email
        )

        fun failure(error: Throwable) = FirebaseSignInResult(
            isSuccess = false,
            errorMessage = error.message ?: "Unknown Firebase sign-in error"
        )
    }
}

class AndroidGoogleSignInManager(
    private val context: Context
) {
    private val googleSignInClient: GoogleSignInClient
    private val auth: FirebaseAuth = FirebaseAuth.getInstance()

    private var signInCompletion: ((FirebaseSignInResult) -> Unit)? = null

    init {
        val gso = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestIdToken("YOUR_WEB_CLIENT_ID_FROM_FIREBASE_CONSOLE")
            .requestEmail()
            .build()

        googleSignInClient = GoogleSignIn.getClient(context, gso)
    }

    fun startSignInFlow(
        activity: Activity,
        completion: (FirebaseSignInResult) -> Unit
    ) {
        signInCompletion = completion

        val signInIntent = googleSignInClient.signInIntent
        activity.startActivityForResult(signInIntent, RC_SIGN_IN)
    }

    fun handleActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        if (requestCode != RC_SIGN_IN) {
            return
        }

        val task = GoogleSignIn.getSignedInAccountFromIntent(data)

        try {
            val account = task.getResult(ApiException::class.java)
            val idToken = account.idToken

            if (idToken == null) {
                signInCompletion?.invoke(
                    FirebaseSignInResult.failure(
                        IllegalStateException("Google ID token was null.")
                    )
                )
                return
            }

            val credential = GoogleAuthProvider.getCredential(idToken, null)

            auth.signInWithCredential(credential)
                .addOnCompleteListener { firebaseTask ->
                    if (firebaseTask.isSuccessful) {
                        val user = firebaseTask.result?.user

                        signInCompletion?.invoke(
                            FirebaseSignInResult.success(
                                userId = user?.uid,
                                email = user?.email
                            )
                        )
                    } else {
                        signInCompletion?.invoke(
                            FirebaseSignInResult.failure(
                                firebaseTask.exception
                                    ?: IllegalStateException("Firebase sign-in failed.")
                            )
                        )
                    }
                }
        } catch (e: ApiException) {
            signInCompletion?.invoke(FirebaseSignInResult.failure(e))
        }
    }

    companion object {
        const val RC_SIGN_IN = 9001
    }
}
