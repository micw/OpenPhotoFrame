package io.github.micw.openphotoframe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log

/**
 * BroadcastReceiver that restarts the app when it's updated (e.g., via F-Droid).
 * This ensures that alarms are re-registered after an app update.
 */
class PackageReplacedReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "PackageReplacedReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val AUTOSTART_KEY = "flutter.autostart_on_boot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Log.d(TAG, "App was updated (MY_PACKAGE_REPLACED)")
            
            // Check if autostart is enabled
            val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val autostartEnabled = prefs.getBoolean(AUTOSTART_KEY, false)
            
            Log.d(TAG, "Autostart enabled: $autostartEnabled")
            
            if (autostartEnabled) {
                Log.d(TAG, "Restarting MainActivity to re-register alarms")
                val startIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                context.startActivity(startIntent)
            } else {
                Log.d(TAG, "Autostart disabled, not restarting app")
            }
        }
    }
}
