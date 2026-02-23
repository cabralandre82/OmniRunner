package com.omnirunner.watch

import android.app.Application
import android.util.Log
import com.omnirunner.watch.data.sync.DataLayerManager
import com.omnirunner.watch.service.WearWorkoutManager

class OmniRunnerWatchApp : Application() {

    companion object {
        const val TAG = "OmniRunnerWatch"
    }

    /** Workout manager — lives at application scope to survive Activity recreation. */
    lateinit var workoutManager: WearWorkoutManager
        private set

    /** DataLayer sync manager — used by WearWorkoutManager and WearListenerService. */
    lateinit var dataLayerManager: DataLayerManager
        private set

    override fun onCreate() {
        super.onCreate()
        dataLayerManager = DataLayerManager(this)
        workoutManager = WearWorkoutManager(this).apply {
            this.dataLayerManager = this@OmniRunnerWatchApp.dataLayerManager
        }
        Log.d(TAG, "OmniRunnerWatch WearOS app initialized (with DataLayer)")

        // Sync any sessions queued while the app was not running
        dataLayerManager.syncAllOfflineSessions()
    }

    override fun onTerminate() {
        workoutManager.destroy()
        super.onTerminate()
    }
}
