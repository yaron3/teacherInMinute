package teacher.minute

import android.content.Context
import android.util.Log
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

object AndroidLocaleManager {
    private const val TAG = "LocaleManager"

    @Volatile
    private var appContext: Context? = null

    @JvmStatic
    fun initialize(context: Context): String {
        appContext = context.applicationContext
        val deviceTag = deviceLanguageTag()
        val appliedTag = applyLanguageCode(deviceTag)
        Log.i(TAG, "Initialized locale manager deviceTag=$deviceTag appliedTag=$appliedTag")
        return appliedTag
    }

    @JvmStatic
    fun applyLanguageCode(languageCode: String): String {
        val normalizedCode = when (languageCode) {
            "iw" -> "he"
            "" -> deviceLanguageTag()
            else -> languageCode
        }
        val before = Locale.getDefault().toLanguageTag()
        val locale = Locale.forLanguageTag(normalizedCode)
        Locale.setDefault(locale)
        applyResourceLocale(locale)
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(locale.toLanguageTag()))
        val after = Locale.getDefault().toLanguageTag()
        val resourceLocale = appContext
            ?.resources
            ?.configuration
            ?.locales
            ?.get(0)
            ?.toLanguageTag()
            ?: "unknown"
        Log.i(TAG, "Applied locale languageCode=$languageCode normalized=$normalizedCode before=$before after=$after resourceLocale=$resourceLocale")
        return after
    }

    private fun deviceLanguageTag(): String {
        val contextLocale = appContext
            ?.resources
            ?.configuration
            ?.locales
            ?.get(0)
            ?.toLanguageTag()
            ?.takeIf { it.isNotBlank() }
        return contextLocale ?: Locale.getDefault().toLanguageTag()
    }

    @Suppress("DEPRECATION")
    private fun applyResourceLocale(locale: Locale) {
        val context = appContext ?: return
        val configuration = context.resources.configuration
        configuration.setLocale(locale)
        configuration.setLocales(android.os.LocaleList(locale))
        context.resources.updateConfiguration(configuration, context.resources.displayMetrics)
    }
}
