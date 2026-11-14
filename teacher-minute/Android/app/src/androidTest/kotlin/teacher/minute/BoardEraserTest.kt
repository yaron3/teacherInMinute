package teacher.minute

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

/**
 * The board's eraser (IT-1) as Android writes it, against the local Firebase
 * emulators (run through EmulatorTestRunner) and their database rules.
 *
 * AndroidChatManager.eraseStrokes removes the strokes it is given, in one
 * update, and leaves the rest of the board alone.
 *
 * Who may erase what is the database rules' job (a student only their own
 * strokes). These tests cannot see it: the app under test talks to the
 * emulator's bare-project-id namespace, which the emulator serves without
 * database.rules.json.
 */
@RunWith(AndroidJUnit4::class)
class BoardEraserTest {

    private val backend = EmulatorBackend(AndroidFirebaseEmulator.host ?: EmulatorTestRunner.DEFAULT_HOST)

    @After
    fun signOut() {
        runCatching { FirebaseAuth.getInstance().signOut() }
    }

    @Test
    fun aStudentErasesTheirOwnStrokes() {
        assumeTrue("Firebase emulators not running", backend.isRunning())
        val student = signIn("eraser.student")
        val qid = lesson(studentUid = student.uid, teacherUid = "a-teacher")

        AndroidChatManager.eraseStrokes(qid, JSONArray(listOf("mine-1")).toString())
        assertEquals(listOf("mine-2", "theirs-1"), strokeIds(qid))
    }

    @Test
    fun aTeacherErasesAnyStroke() {
        assumeTrue("Firebase emulators not running", backend.isRunning())
        val teacher = signIn("eraser.teacher")
        val qid = lesson(studentUid = "a-student", teacherUid = teacher.uid)

        AndroidChatManager.eraseStrokes(qid, JSONArray(listOf("mine-1", "theirs-1")).toString())
        assertEquals(listOf("mine-2"), strokeIds(qid))
    }

    private fun signIn(prefix: String): EmulatorBackend.Account {
        val account = backend.createAccount(prefix)
        Tasks.await(
            FirebaseAuth.getInstance().signInWithEmailAndPassword(account.email, account.password),
            30, TimeUnit.SECONDS
        )
        return account
    }

    /** A live lesson whose board holds two strokes by the signed-in side and one by the other. */
    private fun lesson(studentUid: String, teacherUid: String): String {
        val qid = "eraser-${System.currentTimeMillis()}-${(1000..9999).random()}"
        val me = FirebaseAuth.getInstance().currentUser!!.uid
        val other = if (me == studentUid) teacherUid else studentUid
        fun stroke(sender: String, createdAt: Int) = JSONObject()
            .put("senderUid", sender)
            .put("createdAt", createdAt)
            .put("points", JSONArray().put(JSONObject().put("x", 10).put("y", 10)).put(JSONObject().put("x", 90).put("y", 90)))
        backend.put("questions/$qid", JSONObject()
            .put("status", "accepted")
            .put("studentUid", studentUid)
            .put("teacherUid", teacherUid)
            .put("board", JSONObject().put("strokes", JSONObject()
                .put("mine-1", stroke(me, 1))
                .put("mine-2", stroke(me, 2))
                .put("theirs-1", stroke(other, 3)))))
        return qid
    }

    private fun strokeIds(qid: String): List<String> =
        backend.childKeys("questions/$qid/board/strokes").sorted()
}
