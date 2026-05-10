package teacher.minute

import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase

object AndroidTeacherPresenceManager {
    private const val TAG = "TeacherPresence"
    private const val DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com"

    @JvmStatic
    fun setCurrentTeacherStatus(status: String) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid == null) {
            Log.w(TAG, "setCurrentTeacherStatus skipped: no current user")
            return
        }

        setTeacherStatus(uid, status)
    }

    @JvmStatic
    fun setTeacherStatus(uid: String, status: String) {
        FirebaseDatabase.getInstance(DATABASE_URL)
            .getReference("teachers")
            .child(uid)
            .child("status")
            .setValue(status)
            .addOnSuccessListener {
                Log.i(TAG, "Wrote teacher status=$status uid=$uid")
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "Failed writing teacher status=$status uid=$uid", error)
            }
    }
}
