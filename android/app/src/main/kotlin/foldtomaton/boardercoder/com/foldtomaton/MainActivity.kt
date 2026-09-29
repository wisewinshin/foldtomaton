package foldtomaton.boardercoder.com.foldtomaton

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
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
import kotlin.math.sin

class MainActivity : FlutterActivity(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var hingeSensor: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    private val synth = SynthEngine()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        hingeSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foldtomaton/hinge_angle",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
                val sensor = hingeSensor
                if (sensor == null) {
                    events.error("NO_HINGE_SENSOR", "TYPE_HINGE_ANGLE is unavailable", null)
                    return
                }
                sensorManager.registerListener(
                    this@MainActivity,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME,
                )
            }

            override fun onCancel(arguments: Any?) {
                sensorManager.unregisterListener(this@MainActivity)
                eventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foldtomaton/hinge",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(hingeSensor != null)
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

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type == Sensor.TYPE_HINGE_ANGLE) {
            eventSink?.success(event.values[0].toDouble())
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onDestroy() {
        if (::sensorManager.isInitialized) sensorManager.unregisterListener(this)
        synth.stop()
        super.onDestroy()
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
                    val localFrequency = frequency.coerceIn(20.0, 18000.0)
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

    @Synchronized
    fun stop() {
        running.set(false)
        worker?.interrupt()
        worker = null
    }

}
