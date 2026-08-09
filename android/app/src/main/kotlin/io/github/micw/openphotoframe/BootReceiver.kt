package io.github.micw.openphotoframe

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import android.util.Log

/**
 * BroadcastReceiver that starts the app when the device boots.
 * Only starts if autostart is enabled in app settings.
 *
 * Android 11+ blocks activity starts from background broadcast receivers
 * (and even from foreground services started by them). Using AlarmManager
 * with a PendingIntent works around this: the alarm fires via the system
 * process, which is whitelisted for background activity starts.
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val AUTOSTART_KEY = "flutter.autostart_on_boot"
        private const val BOOT_ALARM_REQUEST_CODE = 9001
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON") return

        Log.i(TAG, "Boot completed received")

        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val autostartEnabled = prefs.getBoolean(AUTOSTART_KEY, false)
        Log.i(TAG, "Autostart enabled: $autostartEnabled")
        if (!autostartEnabled) return

        // Schedule MainActivity to start in ~3 seconds via AlarmManager.
        // The alarm fires through the system process, bypassing Android 11's
        // background activity start restriction (isBgStartWhitelisted).
        val activityIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            BOOT_ALARM_REQUEST_CODE,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val triggerAt = SystemClock.elapsedRealtime() + 3_000L
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent
        )
        Log.i(TAG, "Scheduled MainActivity launch via AlarmManager in 3s")
    }
}
