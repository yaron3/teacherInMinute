package teacher.minute

import android.content.Intent

/**
 * The system share sheet, for AppShare.swift: SkipUI's `ShareLink` only shares
 * from a tap on itself, and the side menu asks what to share first.
 */
object AndroidShareManager {
    private const val TAG = "AndroidShare"

    @JvmStatic
    fun shareText(text: String) {
        val activity = MainActivity.currentActivity ?: return
        activity.runOnUiThread {
            try {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                activity.startActivity(Intent.createChooser(send, null))
            } catch (error: Throwable) {
                AndroidErrorReporter.report(TAG, "Failed to open the share sheet", error)
            }
        }
    }
}
