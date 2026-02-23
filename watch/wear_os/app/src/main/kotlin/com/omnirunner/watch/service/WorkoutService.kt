package com.omnirunner.watch.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.omnirunner.watch.MainActivity
import com.omnirunner.watch.R

/**
 * Foreground service that keeps the workout alive when the screen is off
 * or the user navigates away from the app.
 *
 * Lifecycle:
 * - Started by [WearWorkoutManager.startWorkout]
 * - Stopped by [WearWorkoutManager.endWorkout]
 *
 * The actual tracking logic lives in [WearWorkoutManager]; this service
 * only provides the Android foreground service scaffold required by the OS.
 */
class WorkoutService : Service() {

    companion object {
        const val TAG = "WorkoutService"
        const val CHANNEL_ID = "omnirunner_workout"
        const val NOTIFICATION_ID = 1001
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "WorkoutService started")
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "WorkoutService destroyed")
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Workout Tracking",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps your workout tracking active"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Omni Runner")
            .setContentText("Workout in progress")
            .setSmallIcon(R.drawable.ic_run)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setContentIntent(pendingIntent)
            .build()
    }
}
