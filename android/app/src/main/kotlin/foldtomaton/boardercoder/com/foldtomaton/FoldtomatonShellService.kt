package foldtomaton.boardercoder.com.foldtomaton

import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.os.Process
import android.os.SystemClock
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.regex.Pattern

/** Shizuku user service: reads only fresh Samsung FoldInteractive angle logs. */
class FoldtomatonShellService : Binder() {
    private var owner = -1
    private var reader: AngleReader? = null

    init {
        attachInterface(null, ShellProtocol.TOKEN)
    }

    override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
        if (code == INTERFACE_TRANSACTION) {
            reply?.writeString(ShellProtocol.TOKEN)
            return true
        }
        if (code == SHIZUKU_DESTROY) {
            reader?.stop()
            System.exit(0)
            return true
        }
        data.enforceInterface(ShellProtocol.TOKEN)
        val caller = getCallingUid()
        if (owner < 0) owner = caller
        if (owner != caller) throw SecurityException("wrong caller")
        val out = reply ?: return false
        when (code) {
            ShellProtocol.PING -> {
                out.writeNoException()
                out.writeBundle(Bundle().apply {
                    putInt("uid", Process.myUid())
                    putInt("pid", Process.myPid())
                })
            }
            ShellProtocol.START_ANGLES -> {
                val action = data.readString() ?: throw IllegalArgumentException("action")
                val callback = data.readStrongBinder() ?: throw IllegalArgumentException("callback")
                reader?.stop()
                reader = AngleReader(action, callback).also { it.start() }
                out.writeNoException()
            }
            ShellProtocol.STOP_ANGLES -> {
                reader?.stop()
                reader = null
                out.writeNoException()
            }
            ShellProtocol.ANGLE_STATUS -> {
                out.writeNoException()
                out.writeBundle(reader?.status() ?: Bundle().apply { putString("state", "not started") })
            }
            else -> return super.onTransact(code, data, reply, flags)
        }
        return true
    }

    private class AngleReader(
        private val action: String,
        private val callback: IBinder,
    ) {
        @Volatile private var process: java.lang.Process? = null
        @Volatile private var stopped = false
        @Volatile private var state = "starting"
        private var lines = 0
        private var parsed = 0
        private var rejected = 0
        private var lastAngle = Float.NaN
        private var lastUptime = 0L

        fun start() {
            Thread({
                var child: java.lang.Process? = null
                try {
                    child = ProcessBuilder(
                        "logcat", "-v", "epoch", "-T", "1",
                        "-s", "SprWallpaper|FoldInteractive:V", "*:S",
                    ).redirectErrorStream(true).start()
                    process = child
                    state = "listening"
                    BufferedReader(InputStreamReader(child.inputStream)).use { input ->
                        while (!stopped) {
                            val line = input.readLine() ?: break
                            lines++
                            val value = parse(line) ?: continue
                            val epoch = line.trim().split(Regex("\\s+"), 2)
                                .firstOrNull()?.toDoubleOrNull()
                            val age = if (epoch == null) Long.MAX_VALUE else
                                System.currentTimeMillis() - (epoch * 1000).toLong()
                            if (age !in -100..1_500) {
                                rejected++
                                continue
                            }
                            parsed++
                            lastAngle = value
                            lastUptime = SystemClock.uptimeMillis() - age.coerceAtLeast(0)
                            state = "receiving"
                            val parcel = Parcel.obtain()
                            try {
                                parcel.writeInterfaceToken(ShellProtocol.CALLBACK_TOKEN)
                                parcel.writeFloat(value)
                                parcel.writeLong(lastUptime)
                                callback.transact(
                                    ShellProtocol.CB_ANGLE,
                                    parcel,
                                    null,
                                    IBinder.FLAG_ONEWAY,
                                )
                            } finally {
                                parcel.recycle()
                            }
                        }
                    }
                    if (!stopped) state = "reader ended"
                } catch (error: Exception) {
                    state = "reader error: ${error.message}"
                } finally {
                    child?.destroy()
                }
            }, "foldtomaton-angle-reader").apply {
                isDaemon = true
                start()
            }
        }

        fun stop() {
            stopped = true
            process?.destroy()
            state = "stopped"
        }

        fun status() = Bundle().apply {
            putString("state", state)
            putInt("lines", lines)
            putInt("parsed", parsed)
            putInt("rejected", rejected)
            putFloat("angle", lastAngle)
            putLong("last", lastUptime)
        }

        private fun parse(line: String): Float? {
            if (!line.contains("SprWallpaper|FoldInteractive") || !line.contains("onCommand:")) return null
            if (!(line.contains("action=$action,") || line.contains("action[$action]"))) return null
            if (!(line.contains("isVisible=true") || line.contains("isVisible[true]"))) return null
            val match = ANGLE.matcher(line)
            if (!match.find()) return null
            return match.group(1)?.toFloatOrNull()?.takeIf { it in 0f..180f }
        }

        private companion object {
            val ANGLE: Pattern = Pattern.compile("mCurrentAngle(?:=|\\[)([0-9]+(?:\\.[0-9]+)?)")
        }
    }

    private companion object {
        const val SHIZUKU_DESTROY = 16777115
    }
}
