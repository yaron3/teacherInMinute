package teacher.minute

import android.util.Log
import androidx.activity.ComponentActivity
import com.braintreepayments.api.googlepay.GooglePayClient
import com.braintreepayments.api.googlepay.GooglePayLauncher
import com.braintreepayments.api.googlepay.GooglePayPaymentAuthRequest
import com.braintreepayments.api.googlepay.GooglePayPaymentAuthResult
import com.braintreepayments.api.googlepay.GooglePayReadinessResult
import com.braintreepayments.api.googlepay.GooglePayRequest
import com.braintreepayments.api.googlepay.GooglePayResult
import com.braintreepayments.api.googlepay.GooglePayTotalPriceStatus
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Raises the native Google Pay sheet and tokenizes the result through Braintree,
 * mirroring ApplePayService on iOS: the backend opens a checkout and mints a
 * Braintree client token, this returns a payment method nonce, and
 * `confirmGooglePayPayment` charges it.
 *
 * The blocking `requestPayment` call mirrors AndroidGoogleSignInManager — it must
 * be invoked off the main thread (Swift calls it from a detached Task).
 */
object AndroidGooglePayManager {
    private const val TAG = "AndroidGooglePay"
    private const val TIMEOUT_SECONDS = 300L

    private class PendingPayment {
        val latch = CountDownLatch(1)
        @Volatile var result: String = ""
        @Volatile var error: Throwable? = null
    }

    private val lock = Any()
    private var pendingPayment: PendingPayment? = null

    // GooglePayLauncher registers an Activity Result callback, which Android only
    // permits before the activity reaches STARTED — so it is created once in
    // onCreate and reused, while the client is rebuilt per payment because it
    // is scoped to that checkout's Braintree client token.
    @Volatile private var launcher: GooglePayLauncher? = null
    @Volatile private var client: GooglePayClient? = null

    @JvmStatic
    fun register(activity: ComponentActivity) {
        launcher = GooglePayLauncher(activity) { authResult -> handleLauncherResult(authResult) }
        Log.i(TAG, "Google Pay launcher registered")
    }

    /**
     * Presents the Google Pay sheet and blocks until it resolves. Returns
     * "success|<nonce>" or "cancelled"; throws if Google Pay is unavailable or
     * tokenization fails.
     */
    @JvmStatic
    fun requestPayment(
        clientToken: String,
        currencyCode: String,
        totalPrice: String,
        merchantName: String,
        countryCode: String,
        environment: String
    ): String {
        Log.i(TAG, "requestPayment currency=$currencyCode total=$totalPrice env=$environment")
        val activity = MainActivity.currentActivity
            ?: throw IllegalStateException("No active Android activity")
        val googlePayLauncher = launcher
            ?: throw IllegalStateException("Google Pay launcher was not registered")

        val request = PendingPayment()
        synchronized(lock) {
            if (pendingPayment != null) {
                throw IllegalStateException("Google Pay is already active")
            }
            pendingPayment = request
        }

        activity.runOnUiThread {
            try {
                val payClient = GooglePayClient(activity, clientToken)
                client = payClient

                val payRequest = GooglePayRequest(
                    currencyCode = currencyCode,
                    totalPrice = totalPrice,
                    totalPriceStatus = GooglePayTotalPriceStatus.TOTAL_PRICE_STATUS_FINAL,
                    googleMerchantName = merchantName,
                    countryCode = countryCode,
                    // The sheet is for cards only; PayPal has its own checkout entry.
                    isPayPalEnabled = false
                )
                payRequest.setEnvironment(environment)

                payClient.isReadyToPay(activity) { readiness ->
                    if (readiness !is GooglePayReadinessResult.ReadyToPay) {
                        val readinessError = (readiness as? GooglePayReadinessResult.NotReadyToPay)?.error
                        Log.w(TAG, "Google Pay not ready", readinessError)
                        completePending(
                            error = readinessError
                                ?: IllegalStateException("Google Pay is not available on this device")
                        )
                        return@isReadyToPay
                    }

                    payClient.createPaymentAuthRequest(payRequest) { authRequest ->
                        when (authRequest) {
                            is GooglePayPaymentAuthRequest.ReadyToLaunch -> {
                                Log.i(TAG, "Launching Google Pay sheet")
                                googlePayLauncher.launch(authRequest)
                            }
                            is GooglePayPaymentAuthRequest.Failure -> {
                                Log.e(TAG, "Google Pay auth request failed", authRequest.error)
                                completePending(error = authRequest.error)
                            }
                        }
                    }
                }
            } catch (error: Throwable) {
                Log.e(TAG, "Failed to start Google Pay", error)
                completePending(error = error)
            }
        }

        if (!request.latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            clearPending(request)
            throw IllegalStateException("Timed out waiting for Google Pay")
        }

        request.error?.let { throw it }
        return request.result
    }

    private fun handleLauncherResult(authResult: GooglePayPaymentAuthResult) {
        val payClient = client
        if (payClient == null) {
            completePending(error = IllegalStateException("Missing Google Pay client"))
            return
        }

        payClient.tokenize(authResult) { result ->
            when (result) {
                is GooglePayResult.Success -> {
                    Log.i(TAG, "Google Pay tokenized")
                    completePending(result = "success|" + result.nonce.string)
                }
                is GooglePayResult.Failure -> {
                    Log.e(TAG, "Google Pay tokenization failed", result.error)
                    completePending(error = result.error)
                }
                is GooglePayResult.Cancel -> {
                    Log.i(TAG, "Google Pay cancelled by user")
                    completePending(result = "cancelled")
                }
            }
        }
    }

    private fun completePending(result: String = "", error: Throwable? = null) {
        val request = synchronized(lock) {
            val current = pendingPayment
            pendingPayment = null
            current
        }
        client = null
        request?.result = result
        request?.error = error
        request?.latch?.countDown()
    }

    private fun clearPending(request: PendingPayment) {
        synchronized(lock) {
            if (pendingPayment === request) {
                pendingPayment = null
            }
        }
    }
}
