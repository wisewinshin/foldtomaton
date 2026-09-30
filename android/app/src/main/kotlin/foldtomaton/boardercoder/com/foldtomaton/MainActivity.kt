package foldtomaton.boardercoder.com.foldtomaton

import android.app.WallpaperManager
import android.content.Intent
import android.net.Uri
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    private lateinit var hingeSource: HingeAngleSource
    private lateinit var shizukuFeed: ShizukuAngleFeed
    private lateinit var tiltVibrato: TiltVibratoSource
    private var eventSink: EventChannel.EventSink? = null
    private var vibratoSink: EventChannel.EventSink? = null
    private val synth = SynthEngine()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hingeSource = HingeAngleSource(this) { angle -> eventSink?.success(angle) }
        shizukuFeed = ShizukuAngleFeed(this, hingeSource) { eventSink != null }
        tiltVibrato = TiltVibratoSource(this) { cents ->
            synth.updateVibrato(cents)
            vibratoSink?.success(cents)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foldtomaton/hinge_angle",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
                if (!hingeSource.isAvailable) {
                    events.error("NO_HINGE_SENSOR", "No hinge angle sensor is available", null)
                    return
                }
                if (!hingeSource.start()) {
                    events.error("HINGE_REGISTER_FAILED", "Hinge sensor registration failed", null)
                }
                shizukuFeed.startIfReady()
            }

            override fun onCancel(arguments: Any?) {
                shizukuFeed.stop()
                hingeSource.stop()
                eventSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foldtomaton/tilt_vibrato",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                vibratoSink = events
            }

            override fun onCancel(arguments: Any?) {
                vibratoSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foldtomaton/hinge",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(hingeSource.isAvailable)
                "getStatus" -> result.success(shizukuFeed.status())
                "requestShizukuPermission" -> {
                    result.success(shizukuFeed.bridge.requestPermission())
                }
                "retryContinuousAngle" -> result.success(shizukuFeed.startIfReady())
                "openShizuku" -> result.success(openShizuku())
                "chooseFoldWallpaper" -> result.success(chooseFoldWallpaper())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foldtomaton/audio",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTone" -> {
                    synth.start(
                        call.argument<Double>("frequency") ?: 261.625,
                        call.argument<Double>("cutoff") ?: 8000.0,
                        call.argument<Double>("gain") ?: 0.65,
                    )
                    result.success(null)
                }
                "updateTone" -> {
                    synth.update(
                        call.argument<Double>("frequency") ?: 261.625,
                        call.argument<Double>("cutoff") ?: 8000.0,
                        call.argument<Double>("gain") ?: 0.65,
                    )
                    result.success(null)
                }
                "stopTone" -> {
                    synth.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (::shizukuFeed.isInitialized) {
            shizukuFeed.bridge.refresh()
            shizukuFeed.startIfReady()
        }
        if (::tiltVibrato.isInitialized) tiltVibrato.start()
    }

    override fun onPause() {
        if (::tiltVibrato.isInitialized) tiltVibrato.stop()
        super.onPause()
    }

    private fun openShizuku(): Boolean = runCatching {
        val launch = packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
        startActivity(
            launch ?: Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://shizuku.rikka.app/download/"),
            ),
        )
        true
    }.getOrDefault(false)

    private fun chooseFoldWallpaper(): Boolean = runCatching {
        startActivity(
            Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(
                WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                ShizukuAngleFeed.FOLD_WALLPAPER,
            ),
        )
        true
    }.getOrDefault(false)

    override fun onDestroy() {
        if (::tiltVibrato.isInitialized) tiltVibrato.stop()
        if (::shizukuFeed.isInitialized) shizukuFeed.dispose()
        if (::hingeSource.isInitialized) hingeSource.stop()
        synth.stop()
        super.onDestroy()
    }

    private companion object {
        const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    }
}

private class SynthEngine {
    companion object {
        private const val SAMPLE_RATE = 48000
    }

    private val running = AtomicBoolean(false)
    @Volatile private var frequency = 261.625
    @Volatile private var cutoff = 8000.0
    // DSP gain only. This never reads or changes the Android media volume.
    @Volatile private var gain = 0.65
    @Volatile private var vibratoCents = 0.0
    private var worker: Thread? = null

    @Synchronized
    fun start(frequency: Double, cutoff: Double, gain: Double) {
        update(frequency, cutoff, gain)
        if (running.getAndSet(true)) return

        worker = thread(name = "foldtomaton-synth", isDaemon = true) {
            val minimum = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            val frame = ShortArray(512)
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(max(minimum, frame.size * 8))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            var phase = 0.0
            var filtered = 0.0
            track.play()
            try {
                while (running.get()) {
                    val localFrequency = frequency.coerceIn(20.0, 18000.0) *
                        2.0.pow(vibratoCents.coerceIn(-12.0, 12.0) / 1200.0)
                    val localCutoff = cutoff.coerceIn(50.0, 20000.0)
                    val localGain = gain.coerceIn(0.0, 1.0)
                    val phaseStep = 2.0 * PI * localFrequency / SAMPLE_RATE
                    val alpha = 1.0 - exp(-2.0 * PI * localCutoff / SAMPLE_RATE)
                    for (index in frame.indices) {
                        val raw = sin(phase)
                        filtered += alpha * (raw - filtered)
                        frame[index] = (filtered * localGain * Short.MAX_VALUE * 0.7)
                            .toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()
                        phase += phaseStep
                        if (phase >= 2.0 * PI) phase -= 2.0 * PI
                    }
                    track.write(frame, 0, frame.size, AudioTrack.WRITE_BLOCKING)
                }
            } finally {
                track.pause()
                track.flush()
                track.release()
            }
        }
    }

    fun update(frequency: Double, cutoff: Double, gain: Double) {
        this.frequency = frequency
        this.cutoff = cutoff
        this.gain = gain
    }

    fun updateVibrato(cents: Double) {
        vibratoCents = cents
    }

    @Synchronized
    fun stop() {
        running.set(false)
        worker?.interrupt()
        worker = null
    }

}
