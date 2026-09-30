package foldtomaton.boardercoder.com.foldtomaton

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.util.Log
import rikka.shizuku.Shizuku

/** App-side connection to the minimal Shizuku user service. */
class ShizukuAngleBridge(
    context: Context,
    private val onReady: () -> Unit,
) {
    enum class State { NOT_INSTALLED, NOT_RUNNING, NEEDS_PERMISSION, DENIED, CONNECTING, READY }

    private val appContext = context.applicationContext
    private var service: IBinder? = null
    private var binding = false
    private var angleCallback: AngleCallback? = null

    private val connection = object : android.content.ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            service = binder
            binding = false
            Log.i(TAG, "Shizuku angle service connected")
            onReady()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            service = null
            binding = false
        }
    }

    private val binderListener = Shizuku.OnBinderReceivedListener {
        refresh()
        if (hasPermission) bind()
    }
    private val deadListener = Shizuku.OnBinderDeadListener {
        service = null
        binding = false
    }
    private val permissionListener = Shizuku.OnRequestPermissionResultListener { _, result ->
        if (result == PackageManager.PERMISSION_GRANTED) bind()
    }

    init {
        runCatching {
            Shizuku.addBinderReceivedListenerSticky(binderListener)
            Shizuku.addBinderDeadListener(deadListener)
            Shizuku.addRequestPermissionResultListener(permissionListener)
        }.onFailure { Log.w(TAG, "Unable to initialise Shizuku", it) }
        refresh()
    }

    val installed: Boolean
        get() = runCatching {
            @Suppress("DEPRECATION")
            appContext.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
            true
        }.getOrDefault(false)

    val running: Boolean get() = runCatching { Shizuku.pingBinder() }.getOrDefault(false)

    val hasPermission: Boolean
        get() = running && runCatching {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        }.getOrDefault(false)

    val ready: Boolean get() = hasPermission && service?.isBinderAlive == true

    val state: State
        get() = when {
            !installed && !running -> State.NOT_INSTALLED
            !running -> State.NOT_RUNNING
            hasPermission && ready -> State.READY
            hasPermission -> State.CONNECTING
            runCatching { Shizuku.shouldShowRequestPermissionRationale() }.getOrDefault(false) -> State.DENIED
            else -> State.NEEDS_PERMISSION
        }

    fun refresh() {
        if (hasPermission) bind()
    }

    fun requestPermission(): Boolean {
        if (!running) return false
        if (hasPermission) {
            bind()
            return true
        }
        return runCatching {
            Shizuku.requestPermission(REQUEST_CODE)
            true
        }.getOrElse {
            Log.w(TAG, "Shizuku permission request failed", it)
            false
        }
    }

    private fun args() = Shizuku.UserServiceArgs(
        ComponentName(appContext, FoldtomatonShellService::class.java),
    )
        .daemon(false)
        .processNameSuffix("angle_shell")
        .debuggable(true)
        .version(2)

    private fun bind() {
        if (service != null || binding || !hasPermission) return
        binding = true
        runCatching { Shizuku.bindUserService(args(), connection) }
            .onFailure {
                binding = false
                Log.w(TAG, "Unable to bind Shizuku service", it)
            }
    }

    private fun call(code: Int, write: (Parcel) -> Unit = {}): Bundle? {
        val binder = service ?: return null
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        return try {
            data.writeInterfaceToken(ShellProtocol.TOKEN)
            write(data)
            if (!binder.transact(code, data, reply, 0)) return null
            reply.readException()
            if (reply.dataAvail() > 0) reply.readBundle(javaClass.classLoader) else Bundle()
        } catch (error: Exception) {
            Log.w(TAG, "Shizuku call $code failed", error)
            null
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    private class AngleCallback(private val onAngle: (Float) -> Unit) : Binder() {
        init {
            attachInterface(null, ShellProtocol.CALLBACK_TOKEN)
        }

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code != ShellProtocol.CB_ANGLE) return super.onTransact(code, data, reply, flags)
            data.enforceInterface(ShellProtocol.CALLBACK_TOKEN)
            onAngle(data.readFloat())
            if (data.dataAvail() >= java.lang.Long.BYTES) data.readLong()
            return true
        }
    }

    fun startAngles(action: String, onAngle: (Float) -> Unit): Boolean {
        val callback = AngleCallback(onAngle)
        angleCallback = callback
        return call(ShellProtocol.START_ANGLES) {
            it.writeString(action)
            it.writeStrongBinder(callback)
        } != null
    }

    fun stopAngles() {
        call(ShellProtocol.STOP_ANGLES)
        angleCallback = null
    }

    fun angleStatus(): Bundle? = call(ShellProtocol.ANGLE_STATUS)

    fun dispose() {
        stopAngles()
        runCatching { Shizuku.removeBinderReceivedListener(binderListener) }
        runCatching { Shizuku.removeBinderDeadListener(deadListener) }
        runCatching { Shizuku.removeRequestPermissionResultListener(permissionListener) }
    }

    private companion object {
        const val TAG = "FoldtomatonShizuku"
        const val REQUEST_CODE = 7311
        const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    }
}
