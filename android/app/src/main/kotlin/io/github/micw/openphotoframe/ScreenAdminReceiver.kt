package io.github.micw.openphotoframe

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device Admin Receiver for screen control (lockNow).
 * 
 * The user must enable this in Settings > Security > Device Administrators
 * for the lockNow() functionality to work.
 */
class ScreenAdminReceiver : DeviceAdminReceiver() {
    companion object {
        private const val TAG = "ScreenAdminReceiver"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Device Admin enabled")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.d(TAG, "Device Admin disabled")
    }
}
