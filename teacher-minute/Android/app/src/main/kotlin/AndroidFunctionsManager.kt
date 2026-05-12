package teacher.minute

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object AndroidFunctionsManager {
    private const val TAG = "AndroidFunctionsManager"
    private const val TIMEOUT_MS = 15_000

    @JvmStatic
    fun callFunction(baseUrl: String, functionName: String, payloadJson: String): String {
        val executor = Executors.newSingleThreadExecutor()
        return try {
            executor.submit<String> {
                callFunctionBlocking(baseUrl, functionName, payloadJson)
            }.get()
        } catch (error: ExecutionException) {
            throw error.cause ?: error
        } finally {
            executor.shutdown()
        }
    }

    private fun callFunctionBlocking(baseUrl: String, functionName: String, payloadJson: String): String {
        Log.i(TAG, "Preparing function $functionName")
        val token = currentUserIdToken()
        val connection = URL("$baseUrl/$functionName").openConnection() as HttpURLConnection

        try {
            Log.i(TAG, "Calling function $functionName")

            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.useCaches = false
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.doOutput = true

            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(payloadJson)
            }

            val responseCode = connection.responseCode
            val stream = if (responseCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream ?: connection.inputStream
            }

            val response = BufferedReader(stream.reader(Charsets.UTF_8)).use { reader ->
                reader.readText()
            }
            Log.i(TAG, "Function $functionName returned HTTP $responseCode")
            return response
        } catch (error: Throwable) {
            Log.e(TAG, "Function $functionName failed", error)
            throw error
        } finally {
            connection.disconnect()
        }
    }

    private fun currentUserIdToken(): String {
        val user = FirebaseAuth.getInstance().currentUser
            ?: throw IllegalStateException("Not signed in")
        val result = Tasks.await(user.getIdToken(false), TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        return result.token ?: throw IllegalStateException("Firebase ID token was empty")
    }
}
