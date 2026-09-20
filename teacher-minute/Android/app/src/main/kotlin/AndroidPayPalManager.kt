package teacher.minute

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import com.braintreepayments.api.paypal.PayPalClient
import com.braintreepayments.api.paypal.PayPalLauncher
import com.braintreepayments.api.paypal.PayPalPaymentAuthRequest
import com.braintreepayments.api.paypal.PayPalPaymentAuthResult
import com.braintreepayments.api.paypal.PayPalPendingRequest
import com.braintreepayments.api.paypal.PayPalResult
import com.braintreepayments.api.paypal.PayPalVaultRequest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Runs Braintree's PayPal vault flow so a teacher can confirm the PayPal
 * account their payout is sent to. Mirrors PayPalVaultService on iOS: this
 * returns a payment method nonce, and `verifyPayPalPayoutAccount` exchanges it
 * server-side for the account's authoritative email.
 *
 * ## Why this is not shaped like AndroidGooglePayManager
 *
 * Google Pay is an in-process Activity Result, so blocking a background thread
 * on a latch is safe — the activity stays alive the whole time. PayPal is a
 * **browser switch**: the app goes to the background, and Android may kill the
 * process while the buyer is in the browser. Two consequences:
 *
 *  1. `PayPalPendingRequest.Started.pendingRequestString` must be persisted, so
 *     the return can be matched even if this object was recreated. It is
 *     written to SharedPreferences the moment the browser opens.
 *  2. If the process really was killed, the Swift continuation waiting on the
 *     latch is gone with it — there is nothing left to deliver a nonce to. The
 *     stored request is then simply cleared and the teacher taps Connect again.
 *     That is the honest behaviour; pretending otherwise would hang the UI.
 *
 * The blocking `requestVaultNonce` call must be invoked off the main thread
 * (Swift calls it from a detached Task), like the other managers here.
 */
object AndroidPayPalManager {
    private const val TAG = "AndroidPayPal"
    private const val TIMEOUT_SECONDS = 300L
    private const val PREFS = "braintree_paypal"
    private const val KEY_PENDING = "pending_request"

    /**
     * Must match the App Link registered in the Braintree Control Panel and the
     * autoVerify intent-filter in AndroidManifest.xml, and must be served by
     * assetlinks.json at that host. Braintree v5 requires an https App Link for
     * PayPal — a custom scheme alone is rejected.
     */
    private const val APP_LINK_RETURN_URL = "https://teacher-in-a-moment.web.app/paypal"
    private const val RETURN_URL_SCHEME = "teacherminute"

    private class PendingVault {
        val latch = CountDownLatch(1)
        @Volatile var result: String = ""
        @Volatile var error: Throwable? = null
    }

    private val lock = Any()
    private var pendingVault: PendingVault? = null

    // Rebuilt per request: the client is scoped to that request's Braintree
    // client token. The launcher is stateless and safe to reuse.
    @Volatile private var client: PayPalClient? = null
    private val launcher = PayPalLauncher()

    /**
     * Starts the PayPal vault flow and blocks until it resolves. Returns
     * "success|<nonce>" or "cancelled"; throws if PayPal could not be started.
     */
    @JvmStatic
    fun requestVaultNonce(clientToken: String): String {
        Log.i(TAG, "requestVaultNonce")
        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")

        val request = PendingVault()
        synchronized(lock) {
            if (pendingVault != null) {
                throw IllegalStateException("PayPal is already active")
            }
            pendingVault = request
        }

        activity.runOnUiThread {
            try {
                val payPalClient = PayPalClient(
                    activity,
                    clientToken,
                    Uri.parse(APP_LINK_RETURN_URL),
                    RETURN_URL_SCHEME
                )
                client = payPalClient

                // hasUserLocationConsent=false: the app collects no location, so
                // it cannot claim consent it never asked for.
                val vaultRequest = PayPalVaultRequest(false)

                payPalClient.createPaymentAuthRequest(activity, vaultRequest) { authRequest ->
                    when (authRequest) {
                        is PayPalPaymentAuthRequest.ReadyToLaunch -> {
                            when (val pending = launcher.launch(activity, authRequest)) {
                                is PayPalPendingRequest.Started -> {
                                    Log.i(TAG, "PayPal browser switch started")
                                    storePendingRequest(activity, pending.pendingRequestString)
                                }
                                is PayPalPendingRequest.Failure -> {
                                    Log.e(TAG, "PayPal launch failed", pending.error)
                                    completePending(error = pending.error)
                                }
                            }
                        }
                        is PayPalPaymentAuthRequest.Failure -> {
                            Log.e(TAG, "PayPal auth request failed", authRequest.error)
                            completePending(error = authRequest.error)
                        }
                    }
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start PayPal", error)
                completePending(error = error)
            }
        }

        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for PayPal")
        }

        request.error?.let { throw it }
        return request.result
    }

    /**
     * Called from MainActivity for every intent that could be a PayPal return.
     * Safe to call with unrelated intents — without a stored pending request
     * this does nothing.
     */
    @JvmStatic
    fun handleReturnToApp(activity: ComponentActivity, intent: Intent?) {
        if (intent == null) return
        val pendingRequestString = loadPendingRequest(activity) ?: return

        val authResult = launcher.handleReturnToApp(
            PayPalPendingRequest.Started(pendingRequestString),
            intent
        )

        when (authResult) {
            is PayPalPaymentAuthResult.Success -> {
                clearStoredPendingRequest(activity)
                tokenize(authResult)
            }
            is PayPalPaymentAuthResult.NoResult -> {
                // Not our intent, or the buyer returned without finishing.
                // Leave the stored request alone so a later intent can match it.
                Log.i(TAG, "PayPal return produced no result yet")
            }
            is PayPalPaymentAuthResult.Failure -> {
                clearStoredPendingRequest(activity)
                Log.e(TAG, "PayPal return failed", authResult.error)
                completePending(error = authResult.error)
            }
        }
    }

    private fun tokenize(authResult: PayPalPaymentAuthResult.Success) {
        val payPalClient = client
        if (payPalClient == null) {
            // The process was killed during the browser switch, so the caller
            // waiting for this nonce no longer exists — see the class comment.
            Log.w(TAG, "PayPal returned but the client is gone; ignoring")
            completePending(error = IllegalStateException("PayPal session was lost"))
            return
        }

        payPalClient.tokenize(authResult) { result ->
            when (result) {
                is PayPalResult.Success -> {
                    Log.i(TAG, "PayPal tokenized")
                    completePending(result = "success|" + result.nonce.string)
                }
                is PayPalResult.Failure -> {
                    Log.e(TAG, "PayPal tokenization failed", result.error)
                    completePending(error = result.error)
                }
                is PayPalResult.Cancel -> {
                    Log.i(TAG, "PayPal cancelled by user")
                    completePending(result = "cancelled")
                }
            }
        }
    }

    // MARK: - Pending request persistence

    private fun storePendingRequest(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, value)
            .apply()
    }

    private fun loadPendingRequest(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PENDING, null)

    private fun clearStoredPendingRequest(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_PENDING)
            .apply()
    }

    private fun completePending(result: String = "", error: Throwable? = null) {
        val request = synchronized(lock) {
            val current = pendingVault
            pendingVault = null
            current
        }
        client = null
        request?.result = result
        request?.error = error
        request?.latch?.countDown()
    }

    private fun clearPending(request: PendingVault) {
        synchronized(lock) {
            if (pendingVault === request) {
                pendingVault = null
            }
        }
    }
}
