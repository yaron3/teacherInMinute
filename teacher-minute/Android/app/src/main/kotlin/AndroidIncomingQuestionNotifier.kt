package teacher.minute

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlin.math.absoluteValue

/**
 * Surfaces a teacher invite that arrived over FCM while the app was not in
 * front.
 *
 * Android delivers invites two ways and they cover different windows. In the
 * foreground the dashboard polls `teacherInvites/{uid}` (see
 * TeacherDashboardViewModel.startAndroidInvitePolling); that poll stops with the
 * app, so everything after backgrounding depends on the push. The backend sends
 * that push data-only (functions/src/fcm.ts, `sendInvitePush`) because a
 * `notification` payload would be posted by the system with no control over its
 * channel, timeout or content — and, more importantly, would not reach
 * `onMessageReceived` at all while backgrounded. Data-only means nothing is
 * shown unless this class shows it.
 *
 * Deliberately not a full-screen intent. An invite is call-like and would suit
 * one, but `USE_FULL_SCREEN_INTENT` is restricted to calling and alarm apps from
 * API 34 and needs a Play Console declaration; a high-importance heads-up
 * notification needs no special grant and degrades sanely everywhere.
 */
object AndroidIncomingQuestionNotifier {
    private const val TAG = "TeacherMinuteFCM"
    private const val CHANNEL_ID = "teacher_minute_incoming_questions"
    private const val CHANNEL_NAME = "Incoming questions"
    private const val CHANNEL_DESCRIPTION =
        "A student is waiting. These are time-limited and expire on their own."

    /** Mirrors INVITE_EXPIRY_SECONDS; only used when the push omits ttlSeconds. */
    private const val FALLBACK_TTL_SECONDS = 90L

    /** Every invite notification carries this so they can be cleared together. */
    private const val GROUP_KEY = "teacher_minute_invites"

    private val liveNotificationIds = mutableSetOf<Int>()

    @JvmStatic
    fun handle(context: Context, data: Map<String, String>) {
        val questionId = data["questionId"]
        if (questionId.isNullOrEmpty()) {
            Log.w(TAG, "incoming_question push with no questionId; ignoring")
            return
        }

        // The dashboard's own poll already renders the invite overlay while the
        // app is in front, so posting here as well would double-announce it.
        if (isAppInForeground()) {
            Log.i(TAG, "incoming_question qid=$questionId ignored — app is in the foreground")
            return
        }

        if (!canPostNotifications(context)) {
            // Expected whenever the teacher declined the permission. They are
            // taken offline for exactly this reason (see
            // TeacherDashboardViewModel.enforceNotificationRequirement), so this
            // is a race — a push already in flight — rather than a broken state.
            Log.i(TAG, "incoming_question qid=$questionId dropped — notifications not permitted")
            return
        }

        val ttlSeconds = data["ttlSeconds"]?.toLongOrNull() ?: FALLBACK_TTL_SECONDS
        val studentName = data["studentName"].orEmpty().ifEmpty { "A student" }
        val topic = data["topic"].orEmpty()
        val questionText = data["questionText"].orEmpty()

        val title = if (topic.isEmpty()) {
            "$studentName needs help"
        } else {
            "$studentName needs help with $topic"
        }

        createChannel(context)

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            // Opening the app restarts the invite poll, which picks the invite
            // up from RTDB and raises the overlay; the id rides along so a
            // later routing change can jump straight to it.
            putExtra("questionId", questionId)
        }
        val notificationId = questionId.hashCode().absoluteValue
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(questionText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(questionText))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setGroup(GROUP_KEY)
            // A wave the teacher never answered is dead once it expires, so the
            // notification retires with it rather than sitting in the shade
            // offering a lesson that is gone.
            .setTimeoutAfter(ttlSeconds * 1000)
            // Later waves for the same question replace this notification, and
            // should alert again rather than update silently.
            .setOnlyAlertOnce(false)
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
        synchronized(liveNotificationIds) { liveNotificationIds.add(notificationId) }
        Log.i(TAG, "posted incoming_question qid=$questionId ttl=${ttlSeconds}s wave=${data["wave"]}")
    }

    /**
     * Clears invite notifications. Called when the app comes to the front: from
     * that moment the in-app overlay is the way an invite is answered, so a
     * lingering entry in the shade can only send the teacher somewhere stale.
     */
    @JvmStatic
    fun cancelAll(context: Context) {
        val manager = NotificationManagerCompat.from(context)
        val ids = synchronized(liveNotificationIds) {
            val copy = liveNotificationIds.toList()
            liveNotificationIds.clear()
            copy
        }
        for (id in ids) manager.cancel(id)
        if (ids.isNotEmpty()) Log.i(TAG, "cleared ${ids.size} invite notification(s)")
    }

    /**
     * Resumed, not merely alive: `currentActivity` outlives a backgrounded
     * activity, so checking it for null would suppress every notification until
     * the process died.
     */
    private fun isAppInForeground(): Boolean = MainActivity.isResumed

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        // Its own channel rather than the shared updates one: a teacher who
        // wants to mute general updates must not thereby mute the only thing
        // that tells them a lesson is waiting, and vice versa.
        val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
            description = CHANNEL_DESCRIPTION
            enableVibration(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .build()
            )
        }
        manager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }
}
