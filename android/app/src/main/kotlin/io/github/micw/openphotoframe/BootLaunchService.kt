package io.github.micw.openphotoframe

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Short-lived foreground service that launches MainActivity on boot.
 *
 * Android 11+ blocks activities started directly from a BroadcastReceiver
 * (background activity start restriction). Starting a foreground service first,
 * then starting the activity from the service, is the supported workaround.
 */
class BootLaunchService : Service() {
    companion object {
        private const val TAG = "BootLaunchService"
        private const val CHANNEL_ID = "boot_launch"
        private const val NOTIFICATION_ID = 2001
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "BootLaunchService started")
        ensureNotificationChannel()

        // Must call startForeground within 5 seconds
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Open Photo Frame")
            .setContentText("Starting…")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(NOTIFICATION_ID, notification)

        // Small delay to let system settle after boot before launching the UI
        Handler(Looper.getMainLooper()).postDelayed({
            Log.d(TAG, "Launching MainActivity")
            val activityIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            startActivity(activityIntent)
            stopSelf()
        }, 1000)

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Boot launch",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
