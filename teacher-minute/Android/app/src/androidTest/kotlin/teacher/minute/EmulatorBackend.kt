package teacher.minute

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * The test's own line to the local Firebase emulators, over their REST APIs —
 * the Android twin of the iOS UI tests' `EmulatorBackend.swift`. It creates
 * accounts, writes the data a scene needs, reads back what the app and the
 * backend did, and plays other people by calling the real functions.
 *
 * Admin writes go in as the emulators' `owner`, which skips the security rules.
 * Everything exists only in the emulators, under a demo project.
 */
class EmulatorBackend(private val host: String) {
    private val projectId = AndroidFirebaseEmulator.PROJECT_ID
    private val authBase = "http://$host:9099"
    private val firestoreBase = "http://$host:8085/v1/projects/$projectId/databases/(default)/documents"
    private val databaseBase = "http://$host:9000"
    private val functionsBase = "http://$host:5001/$projectId/us-central1"

    data class Account(val uid: String, val email: String, val password: String, val idToken: String)

    /** What a callable answered: success, or the refusal's status and reason. */
    data class CallOutcome(
        val succeeded: Boolean,
        val status: String?,
        val reason: String?,
        val message: String?,
        val result: JSONObject? = null,
    )

    fun isRunning(): Boolean = try {
        request("GET", "$authBase/", null, owner = false, timeoutMs = 3_000)
        request("GET", "$functionsBase/acceptInvite", null, owner = false, timeoutMs = 3_000)
        true
    } catch (error: Exception) {
        false
    }

    // Auth

    fun createAccount(prefix: String): Account {
        val email = "$prefix.${System.currentTimeMillis()}.${(100..999).random()}@example.com"
        val password = "Emulator-${(100_000..999_999).random()}"
        val body = JSONObject().put("email", email).put("password", password).put("returnSecureToken", true)
        val (status, text) = request(
            "POST", "$authBase/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator", body, owner = false
        )
        check(status in 200..299) { "signUp failed: $status $text" }
        val json = JSONObject(text)
        return Account(json.getString("localId"), email, password, json.getString("idToken"))
    }

    /** True when the Auth emulator accepts these credentials. */
    fun canSignIn(account: Account): Boolean {
        val body = JSONObject().put("email", account.email).put("password", account.password).put("returnSecureToken", true)
        val (status, _) = request(
            "POST", "$authBase/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator", body, owner = false
        )
        return status in 200..299
    }

    /** An address no account on the emulators has yet, for a test that signs up. */
    fun newEmail(prefix: String): String = "$prefix.${System.currentTimeMillis()}.${(100..999).random()}@example.com"

    /** Every Auth user with this address: its uid and sign-in providers. */
    fun users(withEmail: String): List<Pair<String, List<String>>> {
        val body = JSONObject().put("email", JSONArray().put(withEmail))
        val (status, text) = request(
            "POST", "$authBase/identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup", body
        )
        check(status in 200..299) { "accounts:lookup failed: $status $text" }
        val users = JSONObject(text).optJSONArray("users") ?: return emptyList()
        return (0 until users.length()).map { index ->
            val user = users.getJSONObject(index)
            val info = user.optJSONArray("providerUserInfo") ?: JSONArray()
            user.optString("localId") to (0 until info.length()).map { info.getJSONObject(it).optString("providerId") }
        }
    }

    /** An Auth user as the emulator reports it; `createdAt` is in ms. */
    data class AuthUser(val uid: String, val providers: List<String>, val createdAt: Long) {
        val isAnonymous: Boolean get() = providers.isEmpty()
    }

    /** Every Auth user on the emulator. */
    fun allUsers(): List<AuthUser> {
        val (status, text) = request(
            "POST", "$authBase/identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:query",
            JSONObject().put("returnUserInfo", true)
        )
        check(status in 200..299) { "accounts:query failed: $status $text" }
        val users = JSONObject(text).optJSONArray("userInfo") ?: return emptyList()
        return (0 until users.length()).map { authUser(users.getJSONObject(it)) }
    }

    /** The Auth user with this uid, or null if there is none. */
    fun user(uid: String): AuthUser? {
        val (status, text) = request(
            "POST", "$authBase/identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:lookup",
            JSONObject().put("localId", JSONArray().put(uid))
        )
        check(status in 200..299) { "accounts:lookup failed: $status $text" }
        val users = JSONObject(text).optJSONArray("users") ?: return null
        return if (users.length() == 0) null else authUser(users.getJSONObject(0))
    }

    private fun authUser(user: JSONObject): AuthUser {
        val info = user.optJSONArray("providerUserInfo") ?: JSONArray()
        return AuthUser(
            user.optString("localId"),
            (0 until info.length()).map { info.getJSONObject(it).optString("providerId") },
            user.optString("createdAt").toLongOrNull() ?: 0L,
        )
    }

    // Firestore

    /** How many documents in `collection` have `field` equal to `value`. */
    fun count(collection: String, field: String, value: String): Int = documentIds(collection, field, value).size

    /** The ids of the documents in `collection` whose `field` equals `value`. */
    fun documentIds(collection: String, field: String, value: String): List<String> {
        val query = JSONObject().put(
            "structuredQuery",
            JSONObject()
                .put("from", JSONArray().put(JSONObject().put("collectionId", collection)))
                .put(
                    "where", JSONObject().put(
                        "fieldFilter", JSONObject()
                            .put("field", JSONObject().put("fieldPath", field))
                            .put("op", "EQUAL")
                            .put("value", JSONObject().put("stringValue", value))
                    )
                )
        )
        val (status, text) = request("POST", "$firestoreBase:runQuery", query)
        check(status in 200..299) { "runQuery $collection failed: $status $text" }
        val rows = JSONArray(text)
        return (0 until rows.length()).mapNotNull {
            rows.getJSONObject(it).optJSONObject("document")?.optString("name")?.substringAfterLast('/')
        }
    }

    /** The document's fields in Firestore's REST encoding, or null if it does
     *  not exist — for values `strings` cannot show, such as maps. */
    fun fields(path: String): JSONObject? {
        val (status, text) = request("GET", "$firestoreBase/$path", null)
        if (status == 404) return null
        check(status in 200..299) { "GET $path failed: $status $text" }
        return JSONObject(text).optJSONObject("fields") ?: JSONObject()
    }

    /** The strings in the document's array field `field`; empty when either
     *  is missing. */
    fun stringArray(path: String, field: String): List<String> {
        val values = fields(path)?.optJSONObject(field)?.optJSONObject("arrayValue")?.optJSONArray("values")
            ?: return emptyList()
        return (0 until values.length()).mapNotNull { values.getJSONObject(it).optString("stringValue", "").ifEmpty { null } }
    }

    /** Merges `fields` into the document, creating it if needed. */
    fun merge(path: String, fields: Map<String, Any>) {
        val mask = fields.keys.joinToString("&") { "updateMask.fieldPaths=$it" }
        val encoded = JSONObject()
        fields.forEach { (key, value) -> encoded.put(key, firestoreValue(value)) }
        val (status, text) = request("PATCH", "$firestoreBase/$path?$mask", JSONObject().put("fields", encoded))
        check(status in 200..299) { "PATCH $path failed: $status $text" }
    }

    /** The document's string fields, or null if it does not exist. */
    fun strings(path: String): Map<String, String>? {
        val (status, text) = request("GET", "$firestoreBase/$path", null)
        if (status == 404) return null
        check(status in 200..299) { "GET $path failed: $status $text" }
        val fields = JSONObject(text).optJSONObject("fields") ?: return emptyMap()
        val result = mutableMapOf<String, String>()
        for (key in fields.keys()) {
            fields.getJSONObject(key).optString("stringValue", "").takeIf { it.isNotEmpty() }?.let { result[key] = it }
        }
        return result
    }

    private fun firestoreValue(value: Any): JSONObject = when (value) {
        is Boolean -> JSONObject().put("booleanValue", value)
        is Int, is Long -> JSONObject().put("integerValue", value.toString())
        is Double -> JSONObject().put("doubleValue", value)
        is String -> JSONObject().put("stringValue", value)
        is Date -> JSONObject().put("timestampValue", iso8601(value))
        is List<*> -> JSONObject().put(
            "arrayValue",
            JSONObject().put("values", JSONArray(value.filterNotNull().map { firestoreValue(it) }))
        )
        is Map<*, *> -> {
            val fields = JSONObject()
            value.forEach { (key, item) -> if (item != null) fields.put(key.toString(), firestoreValue(item)) }
            JSONObject().put("mapValue", JSONObject().put("fields", fields))
        }
        else -> JSONObject().put("nullValue", JSONObject.NULL)
    }

    private fun iso8601(date: Date): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(date)

    // Realtime Database — the namespace the Functions emulator uses for a demo
    // project is the bare project id.

    fun put(path: String, value: JSONObject) {
        val (status, text) = request("PUT", "$databaseBase/$path.json?ns=$projectId", value)
        check(status in 200..299) { "PUT $path failed: $status $text" }
    }

    /** Merges `value` into what is stored at `path`. */
    fun patch(path: String, value: JSONObject) {
        val (status, text) = request("PATCH", "$databaseBase/$path.json?ns=$projectId", value)
        check(status in 200..299) { "PATCH $path failed: $status $text" }
    }

    /** What is stored at `path`, as org.json decodes it; null when nothing is. */
    fun value(path: String): Any? {
        val (_, text) = request("GET", "$databaseBase/$path.json?ns=$projectId", null)
        val decoded = org.json.JSONTokener(text.ifBlank { "null" }).nextValue()
        return if (decoded == JSONObject.NULL) null else decoded
    }

    fun exists(path: String): Boolean = value(path) != null

    /** The names of the children of `path`, without their contents. */
    fun childKeys(path: String): List<String> {
        val (_, text) = request("GET", "$databaseBase/$path.json?ns=$projectId&shallow=true", null)
        val decoded = org.json.JSONTokener(text.ifBlank { "null" }).nextValue()
        return (decoded as? JSONObject)?.keys()?.asSequence()?.toList() ?: emptyList()
    }

    // Functions

    /** Calls a callable as `account`, the way the apps do. */
    fun call(function: String, account: Account, data: JSONObject): CallOutcome {
        val (_, text) = request(
            "POST", "$functionsBase/$function", JSONObject().put("data", data),
            owner = false, bearer = account.idToken, timeoutMs = 60_000
        )
        val json = JSONObject(text)
        val error = json.optJSONObject("error")
            ?: return CallOutcome(json.has("result"), null, null, null, json.optJSONObject("result"))
        return CallOutcome(
            succeeded = false,
            status = error.optString("status").ifEmpty { null },
            reason = error.optJSONObject("details")?.optString("reason")?.ifEmpty { null },
            message = error.optString("message").ifEmpty { null },
        )
    }

    // Transport

    private fun request(
        method: String,
        url: String,
        body: JSONObject?,
        owner: Boolean = true,
        bearer: String? = null,
        timeoutMs: Int = 30_000,
    ): Pair<Int, String> {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            // Android's HttpURLConnection (unlike the JDK's) accepts PATCH.
            connection.requestMethod = method
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            when {
                bearer != null -> connection.setRequestProperty("Authorization", "Bearer $bearer")
                owner -> connection.setRequestProperty("Authorization", "Bearer owner")
            }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray()) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            return status to text
        } finally {
            connection.disconnect()
        }
    }
}
