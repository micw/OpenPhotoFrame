package io.github.micw.openphotoframe

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * BroadcastReceiver that wakes up the screen when triggered by AlarmManager.
 * 
 * Implements delayed start with retry logic to avoid Binder crashes during system wake-up.
 */
class WakeReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "WakeReceiver"
        private const val WAKE_LOCK_TAG = "OpenPhotoFrame:WakeUp"
        private const val INITIAL_DELAY_MS = 3000L // Wait 3s to avoid Binder crash window
        private const val CHECK_DELAY_MS = 5000L   // Check after 5s if activity is running
        private const val MAX_RETRIES = 2
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Wake alarm received!")
        
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        
        // Acquire a wake lock to turn on the screen
        @Suppress("DEPRECATION")
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
            PowerManager.ACQUIRE_CAUSES_WAKEUP or 
            PowerManager.ON_AFTER_RELEASE,
            WAKE_LOCK_TAG
        )
        
        // Hold wake lock for up to 30 seconds (enough for retries)
        wakeLock.acquire(30_000)
        
        Log.d(TAG, "Screen wake lock acquired, delaying MainActivity start by ${INITIAL_DELAY_MS}ms to avoid Binder crash")
        
        // Delay initial start to avoid Binder/AlarmManager deadlock during wake-up
        Handler(Looper.getMainLooper()).postDelayed({
            tryStartMainActivity(context, wakeLock, 0)
        }, INITIAL_DELAY_MS)
    }
    
    private fun tryStartMainActivity(
        context: Context,
        wakeLock: PowerManager.WakeLock,
        retryCount: Int
    ) {
        try {
            Log.d(TAG, "Starting MainActivity (attempt ${retryCount + 1}/${MAX_RETRIES + 1})")
            
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            context.startActivity(launchIntent)
            
            // Schedule check to verify MainActivity is running
            Handler(Looper.getMainLooper()).postDelayed({
                checkAndRetry(context, wakeLock, retryCount)
            }, CHECK_DELAY_MS)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start MainActivity (attempt ${retryCount + 1})", e)
            
            if (retryCount < MAX_RETRIES) {
                Log.w(TAG, "Retrying in ${CHECK_DELAY_MS}ms...")
                Handler(Looper.getMainLooper()).postDelayed({
                    tryStartMainActivity(context, wakeLock, retryCount + 1)
                }, CHECK_DELAY_MS)
            } else {
                Log.e(TAG, "Max retries reached, giving up")
                releaseWakeLock(wakeLock)
            }
        }
    }
    
    private fun checkAndRetry(
        context: Context,
        wakeLock: PowerManager.WakeLock,
        retryCount: Int
    ) {
        if (isMainActivityRunning(context)) {
            Log.d(TAG, "MainActivity is running successfully")
            releaseWakeLock(wakeLock)
        } else {
            Log.w(TAG, "MainActivity is not running after ${CHECK_DELAY_MS}ms")
            
            if (retryCount < MAX_RETRIES) {
                Log.w(TAG, "Retrying start (${retryCount + 1}/${MAX_RETRIES})...")
                tryStartMainActivity(context, wakeLock, retryCount + 1)
            } else {
                Log.e(TAG, "Max retries reached, MainActivity still not running")
                releaseWakeLock(wakeLock)
            }
        }
    }
    
    private fun isMainActivityRunning(context: Context): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            @Suppress("DEPRECATION")
            val tasks = am.getRunningTasks(1)
            val isRunning = tasks.firstOrNull()?.topActivity?.let { 
                it.packageName == context.packageName &&
                it.className.contains("MainActivity")
            } ?: false
            
            Log.d(TAG, "MainActivity running check: $isRunning")
            isRunning
        } catch (e: Exception) {
            Log.e(TAG, "Error checking if MainActivity is running", e)
            false
        }
    }
    
    private fun releaseWakeLock(wakeLock: PowerManager.WakeLock) {
        try {
            if (wakeLock.isHeld) {
                wakeLock.release()
                Log.d(TAG, "Wake lock released")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wake lock", e)
        }
    }
}
