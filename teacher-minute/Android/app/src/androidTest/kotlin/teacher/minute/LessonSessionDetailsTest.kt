package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

/**
 * What the Android lesson screen reads of a live question, against the local
 * Firebase emulators (run through EmulatorTestRunner).
 *
 * ChatSessionService reads a question node without a `status` as a stub left
 * after the lesson ended. AndroidChatManager.fetchSessionDetailsJson built its
 * JSON field by field and left `status` out, so every live lesson read as
 * ended the moment the Android side connected: it left at once, and the other
 * side saw it disconnect. A live node's status has to reach the JSON, and a
 * stub's absence of one has to stay absent.
 */
@RunWith(AndroidJUnit4::class)
class LessonSessionDetailsTest {

    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)

    @Before
    fun signIn() {
        assumeTrue("Firebase emulators not running", backend.isRunning())
        val account = backend.createAccount("details.reader")
        Tasks.await(
            FirebaseAuth.getInstance().signInWithEmailAndPassword(account.email, account.password),
            30, TimeUnit.SECONDS
        )
    }

    @After
    fun signOut() {
        runCatching { FirebaseAuth.getInstance().signOut() }
    }

    @Test
    fun aLiveLessonCarriesItsStatus() {
        val qid = newQid()
        backend.put("questions/$qid", JSONObject()
            .put("status", "accepted")
            .put("studentUid", "a-student")
            .put("teacherUid", "a-teacher")
            .put("conversationType", "audio")
            .put("text", "Live lesson"))

        val details = JSONObject(AndroidChatManager.fetchSessionDetailsJson(qid))
        assertEquals("the live lesson's status did not reach the lesson screen", "accepted", details.optString("status"))
        assertEquals("audio", details.optString("conversationType"))
    }

    @Test
    fun aStubLeftAfterTheEndHasNoStatus() {
        val qid = newQid()
        // What a late write under a removed question leaves behind.
        backend.put("questions/$qid", JSONObject().put("chatPaused", JSONObject().put("teacher", false)))

        val details = JSONObject(AndroidChatManager.fetchSessionDetailsJson(qid))
        assertFalse("a stub without a status read as a live lesson: $details", details.has("status"))
    }

    private fun newQid(): String = "details-${System.currentTimeMillis()}-${(1000..9999).random()}"
}
