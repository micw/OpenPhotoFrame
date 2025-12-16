package io.github.micw.openphotoframe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

/**
 * BroadcastReceiver that wakes up the screen when triggered by AlarmManager.
 */
class WakeReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "WakeReceiver"
        private const val WAKE_LOCK_TAG = "OpenPhotoFrame:WakeUp"
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
        
        wakeLock.acquire(5000) // Hold for 5 seconds
        
        Log.d(TAG, "Screen wake lock acquired")
        
        // Also start the MainActivity to bring app to foreground
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        context.startActivity(launchIntent)
    }
}
