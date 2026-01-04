package io.github.micw.openphotoframe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app running in the background.
 * 
 * This prevents the app from being killed by Android's low memory killer,
 * especially on older devices with limited RAM.
 * 
 * The service shows a minimal notification that explains it's keeping the
 * photo frame running.
 */
class KeepAliveService : Service() {
    companion object {
        private const val TAG = "KeepAliveService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "keep_alive_channel"
        private const val CHANNEL_NAME = "Photo Frame Keep Alive"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service started")
        
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // START_STICKY ensures the service is restarted if killed by the system
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        // This is not a bound service
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW // Low importance = no sound, minimal visibility
            ).apply {
                description = "Keeps the photo frame app running in the background"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        // Intent to open the app when tapping the notification
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Photo Frame Active")
            .setContentText("Keeping app running for continuous slideshow")
            .setSmallIcon(R.drawable.ic_notification) // We'll need to add this icon
            .setContentIntent(pendingIntent)
            .setOngoing(true) // Cannot be dismissed by swiping
            .setPriority(NotificationCompat.PRIORITY_LOW) // Minimal intrusion
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
