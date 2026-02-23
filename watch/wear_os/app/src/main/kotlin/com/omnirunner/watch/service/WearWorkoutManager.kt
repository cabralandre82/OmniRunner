package com.omnirunner.watch.service

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseState
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.omnirunner.watch.data.sync.DataLayerManager
import com.omnirunner.watch.domain.models.HeartRateSample
import com.omnirunner.watch.domain.models.LocationSample
import com.omnirunner.watch.domain.usecases.Haversine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Manages the full lifecycle of a WearOS workout:
 * - Health Services ExerciseClient (HR, workout session)
 * - FusedLocationProviderClient (GPS tracking)
 * - Distance via Haversine (consistent with Flutter core and Apple Watch)
 * - Pace calculation
 *
 * Uses Kotlin StateFlow for observable state (Compose-friendly).
 *
 * Architecture reference: docs/WatchArchitecture.md §3.2
 */
class WearWorkoutManager(private val context: Context) {

    companion object {
        private const val TAG = "WearWorkoutManager"
    }

    // ── Public State ────────────────────────────────────────────────

    enum class WorkoutState { IDLE, RUNNING, PAUSED, ENDED }

    private val _state = MutableStateFlow(WorkoutState.IDLE)
    val state: StateFlow<WorkoutState> = _state.asStateFlow()

    private val _currentHeartRate = MutableStateFlow(0)
    val currentHeartRate: StateFlow<Int> = _currentHeartRate.asStateFlow()

    private val _averageHeartRate = MutableStateFlow(0)
    val averageHeartRate: StateFlow<Int> = _averageHeartRate.asStateFlow()

    private val _maxHeartRate = MutableStateFlow(0)
    val maxHeartRate: StateFlow<Int> = _maxHeartRate.asStateFlow()

    private val _totalDistanceMeters = MutableStateFlow(0.0)
    val totalDistanceMeters: StateFlow<Double> = _totalDistanceMeters.asStateFlow()

    private val _elapsedSeconds = MutableStateFlow(0)
    val elapsedSeconds: StateFlow<Int> = _elapsedSeconds.asStateFlow()

    private val _currentPaceSecondsPerKm = MutableStateFlow(0.0)
    val currentPaceSecondsPerKm: StateFlow<Double> = _currentPaceSecondsPerKm.asStateFlow()

    private val _gpsPoints = MutableStateFlow<List<LocationSample>>(emptyList())
    val gpsPoints: StateFlow<List<LocationSample>> = _gpsPoints.asStateFlow()

    private val _hrSamples = MutableStateFlow<List<HeartRateSample>>(emptyList())
    val hrSamples: StateFlow<List<HeartRateSample>> = _hrSamples.asStateFlow()

    private val _hasGpsFix = MutableStateFlow(false)
    val hasGpsFix: StateFlow<Boolean> = _hasGpsFix.asStateFlow()

    /** Unique session identifier (generated on watch, sent to phone). */
    val sessionId: UUID = UUID.randomUUID()

    // ── Coroutine Scope ─────────────────────────────────────────────

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // ── Health Services ─────────────────────────────────────────────

    private val exerciseClient by lazy {
        HealthServices.getClient(context).exerciseClient
    }

    private var exerciseCallbackRegistered = false

    // ── Location ────────────────────────────────────────────────────

    private val fusedLocationClient: FusedLocationProviderClient by lazy {
        LocationServices.getFusedLocationProviderClient(context)
    }

    private var lastLocation: Location? = null
    private var locationCallbackRegistered = false

    // ── Timer ───────────────────────────────────────────────────────

    private var timerJob: Job? = null
    private var startTimeMs: Long = 0L
    private var pauseTimeMs: Long = 0L
    private var accumulatedPauseMs: Long = 0L

    // ── GPS Filters (same thresholds as Apple Watch) ────────────────

    private val maxAccuracyMeters = 20f
    private val minDeltaMeters = 1.0
    private val maxDeltaMeters = 100.0

    // ── HR Statistics ───────────────────────────────────────────────

    private var hrSum = 0L
    private var hrCount = 0

    // ── Connectivity ────────────────────────────────────────────────

    /** Optional reference to the DataLayer sync manager. */
    var dataLayerManager: DataLayerManager? = null

    // ── Haptics ─────────────────────────────────────────────────────

    private val vibrator: Vibrator? by lazy {
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    // ═══════════════════════════════════════════════════════════════
    //  Permissions
    // ═══════════════════════════════════════════════════════════════

    fun hasRequiredPermissions(): Boolean =
        hasPermission(Manifest.permission.BODY_SENSORS) &&
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun hasPermission(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    // ═══════════════════════════════════════════════════════════════
    //  Workout Lifecycle
    // ═══════════════════════════════════════════════════════════════

    /**
     * Start a new outdoor running workout.
     *
     * Flow:
     * 1. Start foreground service (keeps workout alive)
     * 2. Configure and start Health Services ExerciseClient (HR)
     * 3. Start FusedLocationProvider (GPS)
     * 4. Start elapsed-time timer
     */
    fun startWorkout() {
        if (_state.value != WorkoutState.IDLE) return

        scope.launch {
            try {
                startForegroundService()

                val config = ExerciseConfig.builder(ExerciseType.RUNNING)
                    .setDataTypes(setOf(DataType.HEART_RATE_BPM))
                    .setIsAutoPauseAndResumeEnabled(false)
                    .setIsGpsEnabled(false)
                    .build()

                exerciseClient.setUpdateCallback(exerciseUpdateCallback)
                exerciseCallbackRegistered = true

                exerciseClient.startExerciseAsync(config).addListener(
                    { Log.d(TAG, "Exercise started successfully") },
                    ContextCompat.getMainExecutor(context),
                )

                startLocationUpdates()
                startTimer()

                startTimeMs = SystemClock.elapsedRealtime()
                _state.value = WorkoutState.RUNNING

                dataLayerManager?.resetTransferState()
                dataLayerManager?.sendStateUpdate(sessionId.toString(), "running")

                playHaptic(HapticType.START)
                Log.d(TAG, "Workout started — session=$sessionId")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start workout", e)
                stopForegroundService()
            }
        }
    }

    /** Pause the active workout. */
    fun pauseWorkout() {
        if (_state.value != WorkoutState.RUNNING) return

        exerciseClient.pauseExerciseAsync().addListener(
            { Log.d(TAG, "Exercise paused") },
            ContextCompat.getMainExecutor(context),
        )

        pauseTimeMs = SystemClock.elapsedRealtime()
        stopTimer()
        _state.value = WorkoutState.PAUSED

        dataLayerManager?.sendStateUpdate(sessionId.toString(), "paused")
        playHaptic(HapticType.STOP)
    }

    /** Resume a paused workout. */
    fun resumeWorkout() {
        if (_state.value != WorkoutState.PAUSED) return

        exerciseClient.resumeExerciseAsync().addListener(
            { Log.d(TAG, "Exercise resumed") },
            ContextCompat.getMainExecutor(context),
        )

        if (pauseTimeMs > 0) {
            accumulatedPauseMs += SystemClock.elapsedRealtime() - pauseTimeMs
        }
        pauseTimeMs = 0L
        startTimer()
        _state.value = WorkoutState.RUNNING

        dataLayerManager?.sendStateUpdate(sessionId.toString(), "running")
        playHaptic(HapticType.START)
    }

    /**
     * End the workout, stop all tracking, finalize session.
     *
     * After calling this, use [toSessionJSON] to get the exportable data.
     */
    fun endWorkout() {
        val currentState = _state.value
        if (currentState != WorkoutState.RUNNING && currentState != WorkoutState.PAUSED) return

        exerciseClient.endExerciseAsync().addListener(
            { Log.d(TAG, "Exercise ended") },
            ContextCompat.getMainExecutor(context),
        )

        if (exerciseCallbackRegistered) {
            exerciseClient.clearUpdateCallbackAsync(exerciseUpdateCallback)
            exerciseCallbackRegistered = false
        }

        stopLocationUpdates()
        stopTimer()
        stopForegroundService()

        _state.value = WorkoutState.ENDED

        // Transfer completed session to phone
        val sessionData = toSessionJSON()
        dataLayerManager?.transferSession(sessionData)
        dataLayerManager?.sendStateUpdate(sessionId.toString(), "ended")

        playHaptic(HapticType.SUCCESS)
        Log.d(
            TAG,
            "Workout ended — distance=${_totalDistanceMeters.value}m, " +
                "hr_samples=${_hrSamples.value.size}, " +
                "gps_points=${_gpsPoints.value.size}",
        )
    }

    /** Reset all state for a new workout. */
    fun reset() {
        lastLocation = null
        startTimeMs = 0L
        pauseTimeMs = 0L
        accumulatedPauseMs = 0L
        hrSum = 0L
        hrCount = 0

        _currentHeartRate.value = 0
        _averageHeartRate.value = 0
        _maxHeartRate.value = 0
        _totalDistanceMeters.value = 0.0
        _elapsedSeconds.value = 0
        _currentPaceSecondsPerKm.value = 0.0
        _gpsPoints.value = emptyList()
        _hrSamples.value = emptyList()
        _hasGpsFix.value = false

        _state.value = WorkoutState.IDLE
    }

    /** Clean up resources. Call when the manager is no longer needed. */
    fun destroy() {
        stopTimer()
        stopLocationUpdates()
        if (exerciseCallbackRegistered) {
            exerciseClient.clearUpdateCallbackAsync(exerciseUpdateCallback)
            exerciseCallbackRegistered = false
        }
        scope.coroutineContext[Job]?.cancel()
    }

    // ═══════════════════════════════════════════════════════════════
    //  Formatted Accessors
    // ═══════════════════════════════════════════════════════════════

    /** Pace as "M:SS /km" string. Returns "--:--" if insufficient data. */
    fun formattedPace(): String {
        val pace = _currentPaceSecondsPerKm.value
        if (pace <= 0 || pace >= 3600) return "--:--"
        val mins = pace.toInt() / 60
        val secs = pace.toInt() % 60
        return String.format("%d:%02d", mins, secs)
    }

    /** Elapsed time as "H:MM:SS" or "MM:SS" string. */
    fun formattedElapsedTime(): String {
        val total = _elapsedSeconds.value
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) {
            String.format("%d:%02d:%02d", h, m, s)
        } else {
            String.format("%02d:%02d", m, s)
        }
    }

    /** Distance as "X.XX km" string. */
    fun formattedDistance(): String {
        val km = _totalDistanceMeters.value / 1000.0
        return String.format("%.2f km", km)
    }

    // ═══════════════════════════════════════════════════════════════
    //  Session Data Export
    // ═══════════════════════════════════════════════════════════════

    /**
     * Serialize the current session into the shared wire format (JSON map).
     *
     * Same schema as Apple Watch's `toSessionJSON()` — see
     * `docs/WatchArchitecture.md` §5.
     */
    fun toSessionJSON(): Map<String, Any> {
        val endMs = System.currentTimeMillis()
        val startMs = endMs - (SystemClock.elapsedRealtime() - startTimeMs)
        val movingMs = maxOf(0L, (_elapsedSeconds.value * 1000L) - accumulatedPauseMs)

        return mapOf(
            "version" to 1,
            "source" to "wear_os",
            "sessionId" to sessionId.toString(),
            "startMs" to startMs,
            "endMs" to endMs,
            "totalDistanceM" to _totalDistanceMeters.value,
            "movingMs" to movingMs,
            "avgBpm" to _averageHeartRate.value,
            "maxBpm" to _maxHeartRate.value,
            "isVerified" to true,
            "integrityFlags" to emptyList<String>(),
            "points" to _gpsPoints.value.map { pt ->
                mapOf(
                    "lat" to pt.lat,
                    "lng" to pt.lng,
                    "alt" to pt.alt,
                    "accuracy" to pt.accuracy,
                    "speed" to pt.speed,
                    "timestampMs" to pt.timestampMs,
                )
            },
            "hrSamples" to _hrSamples.value.map { s ->
                mapOf(
                    "bpm" to s.bpm,
                    "timestampMs" to s.timestampMs,
                )
            },
        )
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Health Services Callback
    // ═══════════════════════════════════════════════════════════════

    private val exerciseUpdateCallback = object : ExerciseUpdateCallback {

        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            processExerciseUpdate(update)
        }

        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) {
            Log.d(TAG, "Lap summary received")
        }

        override fun onAvailabilityChanged(
            dataType: DataType<*, *>,
            availability: Availability,
        ) {
            Log.d(TAG, "Availability changed: $dataType → $availability")
        }

        override fun onRegistered() {
            Log.d(TAG, "Exercise callback registered")
        }

        override fun onRegistrationFailed(throwable: Throwable) {
            Log.e(TAG, "Exercise callback registration failed", throwable)
        }
    }

    private fun processExerciseUpdate(update: ExerciseUpdate) {
        // Process HR data points
        val hrPoints = update.latestMetrics.getData(DataType.HEART_RATE_BPM)
        for (point in hrPoints) {
            val bpm = point.value.toInt()
            if (bpm <= 0) continue

            _currentHeartRate.value = bpm

            hrSum += bpm
            hrCount++
            _averageHeartRate.value = (hrSum / hrCount).toInt()

            if (bpm > _maxHeartRate.value) {
                _maxHeartRate.value = bpm
            }

            _hrSamples.value = _hrSamples.value + HeartRateSample(
                bpm = bpm,
                timestampMs = System.currentTimeMillis(),
            )
        }

        // Observe exercise state transitions from Health Services
        val exerciseState = update.exerciseStateInfo.state
        when (exerciseState) {
            ExerciseState.ACTIVE -> {
                if (_state.value == WorkoutState.PAUSED) {
                    _state.value = WorkoutState.RUNNING
                }
            }
            ExerciseState.USER_PAUSED, ExerciseState.AUTO_PAUSED -> {
                _state.value = WorkoutState.PAUSED
            }
            ExerciseState.ENDED -> {
                _state.value = WorkoutState.ENDED
            }
            else -> {}
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Location
    // ═══════════════════════════════════════════════════════════════

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) {
            Log.w(TAG, "Location permission not granted, skipping GPS")
            return
        }

        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            1000L,
        )
            .setMinUpdateDistanceMeters(1f)
            .setWaitForAccurateLocation(true)
            .build()

        fusedLocationClient.requestLocationUpdates(
            locationRequest,
            locationCallback,
            Looper.getMainLooper(),
        )
        locationCallbackRegistered = true
        Log.d(TAG, "Location updates started")
    }

    private fun stopLocationUpdates() {
        if (locationCallbackRegistered) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
            locationCallbackRegistered = false
            Log.d(TAG, "Location updates stopped")
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            if (_state.value != WorkoutState.RUNNING) return
            for (location in result.locations) {
                processLocation(location)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: GPS Processing
    // ═══════════════════════════════════════════════════════════════

    private fun processLocation(location: Location) {
        if (!location.hasAccuracy() || location.accuracy > maxAccuracyMeters) {
            return
        }

        if (!_hasGpsFix.value) {
            _hasGpsFix.value = true
        }

        val sample = LocationSample(
            lat = location.latitude,
            lng = location.longitude,
            alt = location.altitude,
            accuracy = location.accuracy,
            speed = maxOf(0f, location.speed),
            timestampMs = location.time,
        )

        val prev = lastLocation
        if (prev != null) {
            val delta = Haversine.distanceMeters(
                lat1 = prev.latitude, lng1 = prev.longitude,
                lat2 = location.latitude, lng2 = location.longitude,
            )

            if (delta >= minDeltaMeters && delta <= maxDeltaMeters) {
                _totalDistanceMeters.value += delta
            }
        }

        _gpsPoints.value = _gpsPoints.value + sample
        lastLocation = location
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Timer
    // ═══════════════════════════════════════════════════════════════

    private fun startTimer() {
        timerJob = scope.launch {
            while (isActive) {
                delay(1000L)
                updateElapsedTime()
            }
        }
    }

    private fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }

    private fun updateElapsedTime() {
        if (_state.value != WorkoutState.RUNNING || startTimeMs == 0L) return

        val now = SystemClock.elapsedRealtime()
        val totalMs = now - startTimeMs - accumulatedPauseMs
        _elapsedSeconds.value = maxOf(0, (totalMs / 1000).toInt())

        updatePace()
        sendLiveSampleIfNeeded()
    }

    /** Send a periodic live sample to the phone (throttled by DataLayerManager). */
    private fun sendLiveSampleIfNeeded() {
        dataLayerManager?.sendLiveSampleIfNeeded(
            sessionId = sessionId.toString(),
            bpm = _currentHeartRate.value,
            paceSecondsPerKm = _currentPaceSecondsPerKm.value,
            distanceM = _totalDistanceMeters.value,
            elapsedS = _elapsedSeconds.value,
        )
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Pace
    // ═══════════════════════════════════════════════════════════════

    private fun updatePace() {
        val distance = _totalDistanceMeters.value
        val elapsed = _elapsedSeconds.value

        if (distance <= 50 || elapsed <= 0) {
            _currentPaceSecondsPerKm.value = 0.0
            return
        }

        val kmCovered = distance / 1000.0
        _currentPaceSecondsPerKm.value = elapsed.toDouble() / kmCovered
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Foreground Service
    // ═══════════════════════════════════════════════════════════════

    private fun startForegroundService() {
        val intent = Intent(context, WorkoutService::class.java)
        ContextCompat.startForegroundService(context, intent)
    }

    private fun stopForegroundService() {
        val intent = Intent(context, WorkoutService::class.java)
        context.stopService(intent)
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Haptics
    // ═══════════════════════════════════════════════════════════════

    private enum class HapticType { START, STOP, SUCCESS }

    private fun playHaptic(type: HapticType) {
        val effect = when (type) {
            HapticType.START -> VibrationEffect.createOneShot(
                100, VibrationEffect.DEFAULT_AMPLITUDE,
            )
            HapticType.STOP -> VibrationEffect.createOneShot(
                50, VibrationEffect.DEFAULT_AMPLITUDE,
            )
            HapticType.SUCCESS -> VibrationEffect.createWaveform(
                longArrayOf(0, 100, 80, 100), intArrayOf(0, 200, 0, 200), -1,
            )
        }
        vibrator?.vibrate(effect)
    }
}
