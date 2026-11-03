package teacher.minute

import android.os.Build

object AndroidDeviceInfoManager {
    /// The Android release, e.g. "14". Native Swift's
    /// `ProcessInfo.operatingSystemVersion` reports the Linux kernel instead
    /// ("6.1.23"), which is what the admin dashboard and support requests
    /// showed before.
    @JvmStatic
    fun osVersion(): String = Build.VERSION.RELEASE ?: ""

    /// Manufacturer and model, e.g. "Google Pixel 3" or "Samsung SM-A205F".
    /// Samsung reports its model code rather than the "Galaxy A20" name.
    @JvmStatic
    fun deviceModel(): String {
        val manufacturer = (Build.MANUFACTURER ?: "").replaceFirstChar { it.uppercase() }
        val model = Build.MODEL ?: ""
        return if (model.startsWith(manufacturer, ignoreCase = true)) model
        else "$manufacturer $model".trim()
    }
}
