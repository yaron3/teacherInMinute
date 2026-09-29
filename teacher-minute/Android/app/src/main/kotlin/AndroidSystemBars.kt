package teacher.minute

import androidx.compose.runtime.mutableStateOf

/**
 * The icons the status and navigation bars draw (`SystemBarIcons.swift`).
 * The app draws edge to edge, so the bars show whatever screen is behind them,
 * and `SyncSystemBarsWithTheme` picks their icons from the theme — dark icons,
 * in light mode, even over the dark brand screens. A screen that knows better
 * says so here, and the theme applies again once it has gone.
 */
object AndroidSystemBars {
    /** A screen's request: dark icons, or light ones, for each bar. */
    internal data class Request(val owner: String, val darkStatusBar: Boolean, val darkNavigationBar: Boolean)

    /** The latest request; null follows the theme. */
    internal val request = mutableStateOf<Request?>(null)

    @JvmStatic
    fun setDarkIcons(owner: String, statusBar: Boolean, navigationBar: Boolean) {
        request.value = Request(owner, statusBar, navigationBar)
    }

    /**
     * Only the screen that made the request can withdraw it: the next screen
     * can appear before the last one has gone, and asked for its own already.
     */
    @JvmStatic
    fun followTheme(owner: String) {
        if (request.value?.owner == owner) {
            request.value = null
        }
    }
}
