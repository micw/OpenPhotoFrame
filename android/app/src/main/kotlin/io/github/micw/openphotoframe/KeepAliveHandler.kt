package io.github.micw.openphotoframe

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles communication between Flutter and the Keep Alive Service.
 * 
 * Provides methods to:
 * - Start/stop the foreground service
 * - Check notification permission status
 * - Request notification permission
 */
class KeepAliveHandler(private val context: Context) {
    companion object {
        private const val TAG = "KeepAliveHandler"
        private const val CHANNEL = "io.github.micw.openphotoframe/keep_alive"
    }

    fun configureChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceRunning" -> {
                    result.success(isServiceRunning())
                }
                "startService" -> {
                    val success = startService()
                    result.success(success)
                }
                "stopService" -> {
                    stopService()
                    result.success(true)
                }
                "hasNotificationPermission" -> {
                    result.success(hasNotificationPermission())
                }
                "shouldRequestNotificationPermission" -> {
                    result.success(shouldRequestNotificationPermission())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Check if the Keep Alive Service is currently running.
     */
    private fun isServiceRunning(): Boolean {
        // Simple check - in a real implementation you might want to track this in SharedPreferences
        // For now we rely on the fact that starting an already running service is idempotent
        return false // Will be updated when we track state
    }

    /**
     * Start the Keep Alive foreground service.
     */
    fun startService(): Boolean {
        return try {
            Log.d(TAG, "Starting Keep Alive Service")
            val intent = Intent(context, KeepAliveService::class.java)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Keep Alive Service", e)
            false
        }
    }

    /**
     * Stop the Keep Alive foreground service.
     */
    fun stopService() {
        try {
            Log.d(TAG, "Stopping Keep Alive Service")
            val intent = Intent(context, KeepAliveService::class.java)
            context.stopService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop Keep Alive Service", e)
        }
    }

    /**
     * Check if notification permission is granted.
     * Always returns true for Android < 13.
     */
    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // No permission needed before Android 13
            return true
        }
        
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Check if we should request notification permission.
     * Returns true only on Android 13+ if permission is not granted.
     */
    private fun shouldRequestNotificationPermission(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && 
               !hasNotificationPermission()
    }
}
