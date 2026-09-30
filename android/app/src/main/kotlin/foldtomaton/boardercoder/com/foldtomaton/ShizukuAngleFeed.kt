package foldtomaton.boardercoder.com.foldtomaton

import android.app.WallpaperManager
import android.content.ComponentName
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.WindowManager

/** Polls Samsung's FoldInteractive wallpaper while the instrument Activity is visible. */
class ShizukuAngleFeed(
    private val activity: MainActivity,
    private val hinge: HingeAngleSource,
    private val isNeeded: () -> Boolean,
) {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var action = ""
    private var lastAngleUptime = 0L

    val bridge = ShizukuAngleBridge(activity) { handler.post { startIfReady() } }
    val active: Boolean get() = running && SystemClock.uptimeMillis() - lastAngleUptime < STALE_MS

    private val poll = object : Runnable {
        override fun run() {
            if (!running) return
            val token = activity.window.decorView.windowToken
            if (token != null) {
                runCatching {
                    WallpaperManager.getInstance(activity)
                        .sendWallpaperCommand(token, action, 0, 0, 0, null)
                }.onFailure { Log.w(TAG, "Wallpaper command failed", it) }
            }
            if (lastAngleUptime != 0L && SystemClock.uptimeMillis() - lastAngleUptime > STALE_MS) {
                hinge.clearExternal()
            }
            handler.postDelayed(this, POLL_MS)
        }
    }

    fun startIfReady(): Boolean {
        if (running) return true
        if (!isNeeded()) return false
        bridge.refresh()
        if (!bridge.ready || !foldWallpaperActive()) return false
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER)
        action = "foldtomaton.angle.READ_${SystemClock.elapsedRealtime()}"
        if (!bridge.startAngles(action) { angle -> handler.post { accept(angle) } }) return false
        running = true
        lastAngleUptime = 0L
        handler.post(poll)
        Log.i(TAG, "Continuous wallpaper angle feed started")
        return true
    }

    fun stop() {
        if (!running) return
        running = false
        handler.removeCallbacks(poll)
        bridge.stopAngles()
        hinge.clearExternal()
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER)
    }

    private fun accept(angle: Float) {
        if (!running) return
        lastAngleUptime = SystemClock.uptimeMillis()
        hinge.feedExternal(angle)
    }

    fun foldWallpaperActive(): Boolean {
        val info = runCatching {
            WallpaperManager.getInstance(activity).wallpaperInfo
        }.getOrNull() ?: return false
        return info.packageName == FOLD_WALLPAPER.packageName &&
            (info.serviceName == FOLD_WALLPAPER.className || info.serviceName.contains("FoldInteractive"))
    }

    fun status(): Map<String, Any> {
        val reader = bridge.angleStatus()
        return mapOf(
            "installed" to bridge.installed,
            "running" to bridge.running,
            "authorized" to bridge.hasPermission,
            "connected" to bridge.ready,
            "wallpaper" to foldWallpaperActive(),
            "continuous" to active,
            "state" to bridge.state.name,
            "reader" to (reader?.getString("state") ?: "inactive"),
            "parsed" to (reader?.getInt("parsed") ?: 0),
        )
    }

    fun dispose() {
        stop()
        bridge.dispose()
    }

    companion object {
        private const val TAG = "FoldtomatonAngleFeed"
        private const val POLL_MS = 33L
        private const val STALE_MS = 2_500L
        val FOLD_WALLPAPER = ComponentName(
            "com.samsung.android.wallpaper.live",
            "com.samsung.android.wallpaper.live.fold.FoldInteractive",
        )
    }
}
