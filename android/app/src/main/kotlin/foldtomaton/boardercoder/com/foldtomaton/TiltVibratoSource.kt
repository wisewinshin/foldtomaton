package foldtomaton.boardercoder.com.foldtomaton

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import kotlin.math.abs

/** Turns gentle changes in device tilt into a small, self-centering pitch offset. */
class TiltVibratoSource(
    context: Context,
    private val onCents: (Double) -> Unit,
) : SensorEventListener {
    private val sensorManager = context.getSystemService(SensorManager::class.java)
    private val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GRAVITY)
        ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private var running = false
    private var baseline = 0.0
    private var smoothedCents = 0.0
    private var lastTimestampNs = 0L
    private var lastEmitUptime = 0L

    fun start(): Boolean {
        if (running) return true
        reset()
        running = sensorManager?.registerListener(
            this,
            sensor,
            SensorManager.SENSOR_DELAY_GAME,
        ) == true
        return running
    }

    fun stop() {
        if (running) sensorManager?.unregisterListener(this)
        running = false
        reset()
        onCents(0.0)
    }

    override fun onSensorChanged(event: SensorEvent) {
        val axis = event.values.getOrNull(1)?.toDouble() ?: return
        val timestamp = event.timestamp
        if (lastTimestampNs == 0L) {
            baseline = axis
            lastTimestampNs = timestamp
            return
        }

        val dt = ((timestamp - lastTimestampNs) / 1_000_000_000.0)
            .coerceIn(0.001, 0.1)
        lastTimestampNs = timestamp

        // The neutral point follows slowly, so a held posture does not detune the note.
        val baselineAlpha = dt / (BASELINE_TIME_SECONDS + dt)
        baseline += baselineAlpha * (axis - baseline)
        val displacement = axis - baseline
        val target = (displacement / SensorManager.GRAVITY_EARTH * CENTS_PER_G)
            .coerceIn(-MAX_CENTS, MAX_CENTS)
            .let { if (abs(it) < DEAD_ZONE_CENTS) 0.0 else it }

        val smoothingAlpha = dt / (SMOOTHING_TIME_SECONDS + dt)
        smoothedCents += smoothingAlpha * (target - smoothedCents)
        if (abs(smoothedCents) < 0.03) smoothedCents = 0.0

        val now = SystemClock.uptimeMillis()
        if (now - lastEmitUptime >= EMIT_INTERVAL_MS) {
            lastEmitUptime = now
            onCents(smoothedCents)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun reset() {
        baseline = 0.0
        smoothedCents = 0.0
        lastTimestampNs = 0L
        lastEmitUptime = 0L
    }

    private companion object {
        const val BASELINE_TIME_SECONDS = 1.1
        const val SMOOTHING_TIME_SECONDS = 0.07
        const val CENTS_PER_G = 28.0
        const val MAX_CENTS = 12.0
        const val DEAD_ZONE_CENTS = 0.35
        const val EMIT_INTERVAL_MS = 25L
    }
}
