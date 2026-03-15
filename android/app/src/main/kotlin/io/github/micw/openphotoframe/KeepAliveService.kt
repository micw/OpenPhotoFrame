package io.github.micw.openphotoframe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app running and auto-restarts MainActivity after crashes.
 * 
 * When the service is restarted by Android after an OOM kill, it checks if MainActivity
 * is running and restarts it if necessary. This ensures the photo frame continues to work
 * even after memory-related crashes.
 * 
 * The service shows a minimal notification that explains it's keeping the
 * photo frame running.
 */
class KeepAliveService : Service() {
    private val restartScheduler by lazy {
        MainActivityRestartScheduler(
            delayedExecutor = HandlerDelayedExecutor(Handler(Looper.getMainLooper())),
            restartDelayMs = RESTART_DELAY_MS,
            restartAction = { ensureMainActivityIsRunning() },
        )
    }

    companion object {
        private const val TAG = "KeepAliveService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "keep_alive_channel"
        private const val CHANNEL_NAME = "Photo Frame Keep Alive"
        private const val RESTART_DELAY_MS = 2000L // Wait 2s before restarting MainActivity
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
        
        // Check if MainActivity needs to be restarted after a delay
        // This happens when the service is restarted by Android after an OOM kill
        restartScheduler.schedule()
        
        // START_STICKY ensures the service is restarted if killed by the system
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        // This is not a bound service
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        restartScheduler.cancel()
        Log.d(TAG, "Service destroyed")
    }
    
    /**
     * Ensures MainActivity is running. If not, starts it.
     * This is called after the service restarts following an OOM kill.
     */
    private fun ensureMainActivityIsRunning() {
        if (!isMainActivityRunning()) {
            Log.w(TAG, "MainActivity is not running, restarting it")
            startMainActivity()
        } else {
            Log.d(TAG, "MainActivity is already running")
        }
    }
    
    /**
     * Checks if MainActivity is currently running.
     */
    private fun isMainActivityRunning(): Boolean {
        val isRunning = MainActivity.isRunning
        Log.d(TAG, "MainActivity running check: $isRunning")
        return isRunning
    }
    
    /**
     * Starts MainActivity.
     */
    private fun startMainActivity() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(intent)
            Log.d(TAG, "MainActivity started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start MainActivity", e)
        }
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
