package com.omnirunner.watch

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.omnirunner.watch.service.WearWorkoutManager
import com.omnirunner.watch.ui.screens.StartScreen
import com.omnirunner.watch.ui.screens.SummaryScreen
import com.omnirunner.watch.ui.screens.WorkoutScreen
import com.omnirunner.watch.ui.theme.OmniRunnerWatchTheme

class MainActivity : ComponentActivity() {

    private val workoutManager: WearWorkoutManager
        get() = (application as OmniRunnerWatchApp).workoutManager

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val allGranted = grants.values.all { it }
        if (allGranted) {
            workoutManager.startWorkout()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        setContent {
            OmniRunnerWatchTheme {
                WatchApp(
                    manager = workoutManager,
                    onStartRequested = ::handleStartRequest,
                )
            }
        }
    }

    private fun handleStartRequest() {
        if (workoutManager.hasRequiredPermissions()) {
            workoutManager.startWorkout()
        } else {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.BODY_SENSORS,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACTIVITY_RECOGNITION,
                ),
            )
        }
    }
}

/**
 * Root composable — routes to the correct screen based on workout state.
 */
@Composable
fun WatchApp(
    manager: WearWorkoutManager,
    onStartRequested: () -> Unit,
) {
    val state by manager.state.collectAsState()

    when (state) {
        WearWorkoutManager.WorkoutState.IDLE -> {
            StartScreen(onStartClick = onStartRequested)
        }
        WearWorkoutManager.WorkoutState.RUNNING,
        WearWorkoutManager.WorkoutState.PAUSED -> {
            WorkoutScreen(manager = manager)
        }
        WearWorkoutManager.WorkoutState.ENDED -> {
            SummaryScreen(manager = manager)
        }
    }
}
