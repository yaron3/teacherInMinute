package teacher.minute

import androidx.compose.runtime.mutableStateListOf

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

    /**
     * Every screen on show that asked, oldest first; the newest decides. A
     * modal asks on top of the screen under it, and when it goes, that
     * screen's request applies again.
     */
    internal val requests = mutableStateListOf<Request>()

    @JvmStatic
    fun setDarkIcons(owner: String, statusBar: Boolean, navigationBar: Boolean) {
        val request = Request(owner, statusBar, navigationBar)
        val index = requests.indexOfFirst { it.owner == owner }
        if (index >= 0) {
            requests[index] = request
        } else {
            requests.add(request)
        }
    }

    /**
     * Withdraws only this screen's request: the next screen can appear before
     * the last one has gone, and has asked for its own already.
     */
    @JvmStatic
    fun followTheme(owner: String) {
        requests.removeAll { it.owner == owner }
    }
}
