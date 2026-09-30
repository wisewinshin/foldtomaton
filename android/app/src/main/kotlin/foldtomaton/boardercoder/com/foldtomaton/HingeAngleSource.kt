package foldtomaton.boardercoder.com.foldtomaton

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import android.os.SystemClock

/** Selects the finest accessible hinge-angle sensor that actually emits data. */
class HingeAngleSource(
    context: Context,
    private val onAngle: (Double) -> Unit,
) : SensorEventListener {
    private data class Candidate(
        val sensor: Sensor,
        var eventCount: Int = 0,
        var registered: Boolean = false,
    ) {
        val resolution: Float
            get() = sensor.resolution.takeIf { it.isFinite() && it > 0f } ?: 1f
    }

    private val sensorManager = context.getSystemService(SensorManager::class.java)
    private val candidates = discover().map(::Candidate)
    private var active: Candidate? = null
    private var started = false
    private var lastExternalUptime = 0L

    val isAvailable: Boolean get() = candidates.isNotEmpty()

    fun start(): Boolean {
        if (started) return candidates.any { it.registered }
        started = true

        for (candidate in candidates) {
            candidate.registered = try {
                sensorManager?.registerListener(
                    this,
                    candidate.sensor,
                    SAMPLING_PERIOD_US,
                ) == true
            } catch (error: SecurityException) {
                // Samsung's continuous folding_angle sensor is signature-only.
                Log.w(TAG, "Denied ${candidate.sensor.name}: ${error.message}")
                false
            }
            Log.i(
                TAG,
                "Candidate ${candidate.sensor.name}, type=${candidate.sensor.stringType}, " +
                    "resolution=${candidate.resolution}, wakeUp=${candidate.sensor.isWakeUpSensor}, " +
                    "registered=${candidate.registered}",
            )
        }
        return candidates.any { it.registered }
    }

    fun stop() {
        if (!started) return
        started = false
        sensorManager?.unregisterListener(this)
        candidates.forEach { it.registered = false }
        active = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (SystemClock.uptimeMillis() - lastExternalUptime < EXTERNAL_STALE_MS) return
        val value = event.values.firstOrNull() ?: return
        if (!value.isFinite() || value !in -5f..185f) return

        val source = candidates.firstOrNull { it.sensor == event.sensor } ?: return
        source.eventCount++

        val best = candidates
            .filter { it.eventCount > 0 }
            .minWithOrNull(
                compareBy<Candidate> { it.resolution }
                    .thenBy { it.sensor.type != Sensor.TYPE_HINGE_ANGLE },
            ) ?: return

        val current = active
        if (current == null || best.resolution < current.resolution) {
            active = best
            Log.i(TAG, "Using ${best.sensor.name}, resolution=${best.resolution}")
        }
        if (active !== source) return

        onAngle(value.coerceIn(0f, 180f).toDouble())
    }

    /** A continuous value supplied by the authorised Shizuku wallpaper reader. */
    fun feedExternal(angle: Float) {
        if (!angle.isFinite() || angle !in 0f..180f) return
        lastExternalUptime = SystemClock.uptimeMillis()
        onAngle(angle.toDouble())
    }

    fun clearExternal() {
        lastExternalUptime = 0L
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun discover(): List<Sensor> {
        val all = runCatching {
            sensorManager?.getSensorList(Sensor.TYPE_ALL)
        }.getOrNull().orEmpty()

        val standard = all
            .filter { it.type == Sensor.TYPE_HINGE_ANGLE }
            .ifEmpty {
                listOfNotNull(sensorManager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE))
            }
            .sortedBy { it.isWakeUpSensor }

        val vendor = all.filter { sensor ->
            if (sensor.type < Sensor.TYPE_DEVICE_PRIVATE_BASE) return@filter false
            val name = "${sensor.name} ${sensor.stringType}".lowercase()
            val foldRelated = name.contains("hinge") || name.contains("fold")
            val degreeRange = sensor.maximumRange.isFinite() &&
                sensor.maximumRange in 150f..360f
            val angleMode = sensor.reportingMode == Sensor.REPORTING_MODE_CONTINUOUS ||
                sensor.reportingMode == Sensor.REPORTING_MODE_ON_CHANGE
            foldRelated && degreeRange && angleMode
        }

        return (standard + vendor).distinctBy {
            "${it.type}|${it.name}|${it.isWakeUpSensor}"
        }
    }

    private companion object {
        const val TAG = "FoldtomatonHinge"
        const val SAMPLING_PERIOD_US = 8_000
        const val EXTERNAL_STALE_MS = 2_500L
    }
}
