package io.github.micw.openphotoframe

import android.app.ActivityManager
import android.app.AlarmManager
import android.os.Debug
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Handles screen control via Flutter Method Channel.
 * 
 * Provides functionality to:
 * - Turn screen off using Device Admin lockNow()
 * - Schedule wake-up using AlarmManager
 * - Wake screen using WakeLock with ACQUIRE_CAUSES_WAKEUP
 */
class ScreenControlHandler(private val context: Context) {
    companion object {
        private const val TAG = "ScreenControlHandler"
        private const val CHANNEL = "io.github.micw.openphotoframe/screen_control"
        private const val WAKE_ACTION = "io.github.micw.openphotoframe.WAKE_SCREEN"
        private const val WAKE_LOCK_TAG = "OpenPhotoFrame:WakeUp"
    }

    private val devicePolicyManager: DevicePolicyManager by lazy {
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    private val powerManager: PowerManager by lazy {
        context.getSystemService(Context.POWER_SERVICE) as PowerManager
    }

    private val alarmManager: AlarmManager by lazy {
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    }

    private val adminComponent: ComponentName by lazy {
        ComponentName(context, ScreenAdminReceiver::class.java)
    }

    fun configureChannel(flutterEngine: FlutterEngine) {
        // The Rockchip RK3326 memtrack HAL has a bug (readdir on null DIR*) that causes
        // it to crash in a loop and eventually destabilise the system. Stop it once on
        // startup — it only feeds diagnostic tools and is not needed for normal operation.
        stopCrashingMemtrackService()
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (prefs.getBoolean("flutter.wifi_adb_enabled", true)) enableWifiAdb()
        if (prefs.getBoolean("flutter.emmc_cache_warm_enabled", false)) warmEmmcFileCache()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceAdminEnabled" -> {
                    result.success(isDeviceAdminEnabled())
                }
                "requestDeviceAdmin" -> {
                    requestDeviceAdmin()
                    result.success(null)
                }
                "openDeviceAdminSettings" -> {
                    openDeviceAdminSettings()
                    result.success(null)
                }
                "openWifiSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_WIFI_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(null)
                }
                "openAndroidSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(null)
                }
                "openDeveloperSettings" -> {
                    val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(null)
                }
                "rebootDevice" -> {
                    try {
                        Runtime.getRuntime().exec(arrayOf("/system/xbin/su", "0", "/system/bin/reboot"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REBOOT_FAILED", e.message, null)
                    }
                }
                "turnScreenOff" -> {
                    val success = turnScreenOff()
                    result.success(success)
                }
                "scheduleWakeUp" -> {
                    val wakeTimeMillis = call.argument<Long>("wakeTimeMillis")
                    if (wakeTimeMillis != null) {
                        scheduleWakeUp(wakeTimeMillis)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "wakeTimeMillis is required", null)
                    }
                }
                "cancelScheduledWakeUp" -> {
                    cancelScheduledWakeUp()
                    result.success(true)
                }
                "wakeScreenNow" -> {
                    wakeScreenNow()
                    result.success(true)
                }
                "isScreenOn" -> {
                    result.success(powerManager.isInteractive)
                }
                "getMemoryInfo" -> {
                    result.success(getMemoryInfo())
                }
                "getThermalInfo" -> {
                    result.success(getThermalInfo())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Check if Device Admin is enabled for this app.
     */
    fun isDeviceAdminEnabled(): Boolean {
        return devicePolicyManager.isAdminActive(adminComponent)
    }

    /**
     * Launch the Device Admin settings to request admin privileges.
     */
    private fun requestDeviceAdmin() {
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Open Photo Frame needs Device Admin permission to turn off the screen at night and wake it up in the morning."
            )
            // Note: Do NOT add FLAG_ACTIVITY_NEW_TASK - DeviceAdminAdd rejects it
        }
        
        // Start from activity context if available
        if (context is android.app.Activity) {
            context.startActivity(intent)
        } else {
            // Fallback with NEW_TASK flag (may not work on all devices)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    /**
     * Open the Device Admin settings where the user can disable this app.
     * Useful for uninstalling the app.
     */
    private fun openDeviceAdminSettings() {
        try {
            // Try to open Device Admin settings directly
            val intent = Intent().apply {
                component = ComponentName("com.android.settings", "com.android.settings.DeviceAdminSettings")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general Security settings if direct access fails
            Log.w(TAG, "Could not open Device Admin settings directly, falling back to Security settings", e)
            val intent = Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }

    /**
     * Turn off the screen using lockNow().
     * Requires Device Admin to be enabled.
     */
    fun turnScreenOff(): Boolean {
        return try {
            if (isDeviceAdminEnabled()) {
                Log.d(TAG, "Turning screen off via lockNow()")
                devicePolicyManager.lockNow()
                true
            } else {
                Log.w(TAG, "Device Admin not enabled, cannot turn screen off")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to turn screen off: ${e.message}")
            false
        }
    }

    /**
     * Schedule a wake-up at the specified time.
     */
    fun scheduleWakeUp(wakeTimeMillis: Long) {
        val intent = Intent(context, WakeReceiver::class.java).apply {
            action = WAKE_ACTION
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Cancel any existing alarm
        alarmManager.cancel(pendingIntent)

        // Schedule new alarm
        Log.d(TAG, "Scheduling wake-up at $wakeTimeMillis (in ${(wakeTimeMillis - System.currentTimeMillis()) / 1000}s)")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // setAlarmClock is the most reliable for waking device
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(wakeTimeMillis, pendingIntent),
                pendingIntent
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, wakeTimeMillis, pendingIntent)
        }
    }

    /**
     * Cancel any scheduled wake-up.
     */
    fun cancelScheduledWakeUp() {
        val intent = Intent(context, WakeReceiver::class.java).apply {
            action = WAKE_ACTION
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Cancelled scheduled wake-up")
    }

    /**
     * Returns Android memory stats for Prometheus metrics.
     */
    private fun getMemoryInfo(): Map<String, Long> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        val rt = Runtime.getRuntime()

        // Read process CPU ticks from /proc/self/stat.
        // Fields 14 (utime) and 15 (stime) are in jiffies (1/100s on Android).
        var cpuJiffies = 0L
        try {
            val parts = java.io.File("/proc/self/stat").readText().trim().split(" ")
            cpuJiffies = parts[13].toLong() + parts[14].toLong()
        } catch (_: Exception) {}

        val result = mutableMapOf(
            "system_avail_mem_bytes" to memInfo.availMem,
            "system_total_mem_bytes" to memInfo.totalMem,
            "system_low_mem_threshold_bytes" to memInfo.threshold,
            "system_low_memory" to if (memInfo.lowMemory) 1L else 0L,
            "jvm_total_bytes" to rt.totalMemory(),
            "jvm_free_bytes" to rt.freeMemory(),
            "jvm_max_bytes" to rt.maxMemory(),
            "process_cpu_jiffies_total" to cpuJiffies,
            "native_heap_allocated_bytes" to Debug.getNativeHeapAllocatedSize(),
            "native_heap_size_bytes" to Debug.getNativeHeapSize(),
        )

        try {
            val storageDir = context.getExternalFilesDir(null) ?: context.filesDir
            val fs = android.os.StatFs(storageDir.absolutePath)
            result["storage_total_bytes"] = fs.totalBytes
            result["storage_free_bytes"] = fs.freeBytes
            result["storage_avail_bytes"] = fs.availableBytes
        } catch (_: Exception) {}

        return result
    }

    /**
     * Returns temperatures from all /sys/class/thermal/thermal_zone* sensors.
     * Keys are the zone type strings (e.g. "cpu", "battery", "gpu").
     * Values are degrees Celsius as doubles.
     * If multiple zones share the same type, they are suffixed _1, _2, etc.
     */
    private fun getThermalInfo(): Map<String, Double> {
        val result = mutableMapOf<String, Double>()
        val thermalDir = java.io.File("/sys/class/thermal")
        if (!thermalDir.exists()) return result

        thermalDir.listFiles()
            ?.filter { it.name.startsWith("thermal_zone") }
            ?.sortedBy { it.name }
            ?.forEach { zone ->
                try {
                    val type = java.io.File(zone, "type").readText().trim()
                        .replace(Regex("[^a-zA-Z0-9_]"), "_")
                    val raw = java.io.File(zone, "temp").readText().trim().toLong()
                    // Most Android devices report millidegrees; a few report degrees directly
                    val celsius = if (raw > 1000) raw / 1000.0 else raw.toDouble()

                    // Skip sentinel values used for absent/disabled sensors
                    if (celsius < -200 || celsius > 200) return@forEach

                    // Deduplicate keys if multiple zones share the same type
                    val key = if (!result.containsKey(type)) type else {
                        var i = 1
                        while (result.containsKey("${type}_$i")) i++
                        "${type}_$i"
                    }
                    result[key] = celsius
                } catch (_: Exception) {}
            }

        return result
    }

    private fun warmEmmcFileCache() {
        // These files sit on eMMC sectors that have shown intermittent I/O errors.
        // Reading them at startup populates the page cache so the kernel does not need
        // to fetch them from the eMMC when a running daemon first touches a cold page.
        val files = listOf(
            "/system/apex/com.android.os.statsd/bin/statsd",
            "/system/bin/audioserver",
            "/system/bin/netd",
            "/system/bin/vdc",
            "/system/bin/wificond",
            "/system/etc/task_profiles.json",
            "/system/lib/libandroid_runtime.so"
        )
        for (path in files) {
            try {
                java.io.File(path).inputStream().use { stream ->
                    val buf = ByteArray(65536)
                    while (stream.read(buf) != -1) { /* discard — just pulling pages into cache */ }
                }
                Log.i(TAG, "eMMC cache warm: $path")
            } catch (e: Exception) {
                Log.w(TAG, "eMMC cache warm failed for $path: ${e.message}")
            }
        }
    }

    private fun enableWifiAdb() {
        try {
            Runtime.getRuntime().exec(arrayOf("/system/xbin/su", "0", "/system/bin/setprop", "service.adb.tcp.port", "5555")).waitFor()
            Runtime.getRuntime().exec(arrayOf("/system/xbin/su", "0", "/system/bin/stop", "adbd")).waitFor()
            Runtime.getRuntime().exec(arrayOf("/system/xbin/su", "0", "/system/bin/start", "adbd"))
            Log.i(TAG, "WiFi ADB enabled on port 5555")
        } catch (e: Exception) {
            Log.d(TAG, "Could not enable WiFi ADB: ${e.message}")
        }
    }

    private fun stopCrashingMemtrackService() {
        // Only applies to Rockchip RK3326 devices — the memtrack HAL on this SoC has a
        // bug (readdir on null DIR*) that causes it to crash in a loop and destabilise
        // the system. It only feeds diagnostic tools so stopping it is safe.
        //
        // The device has SELinux permissive, no PR_SET_NO_NEW_PRIVS, and a setuid-root
        // /system/xbin/su binary — so the app process can escalate to root via su.
        val isRockchip = Build.HARDWARE.contains("rk", ignoreCase = true) ||
                java.io.File("/vendor/lib/hw/memtrack.rk3326.so").exists()
        if (!isRockchip) return
        try {
            val proc = Runtime.getRuntime().exec(
                arrayOf("/system/xbin/su", "0", "/system/bin/stop", "vendor.memtrack-hal-1-0")
            )
            val exit = proc.waitFor()
            if (exit == 0) {
                Log.i(TAG, "Stopped vendor.memtrack-hal-1-0 via su (buggy Rockchip RK3326 HAL)")
            } else {
                Log.w(TAG, "su stop returned exit code $exit, falling back to direct stop")
                Runtime.getRuntime().exec("stop vendor.memtrack-hal-1-0")
            }
        } catch (e: Exception) {
            Log.d(TAG, "Could not stop memtrack service: ${e.message}")
        }
    }

    /**
     * Wake up the screen immediately.
     */
    fun wakeScreenNow() {
        Log.d(TAG, "Waking screen now")
        
        @Suppress("DEPRECATION")
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or 
            PowerManager.ACQUIRE_CAUSES_WAKEUP or 
            PowerManager.ON_AFTER_RELEASE,
            WAKE_LOCK_TAG
        )
        
        wakeLock.acquire(3000) // Hold for 3 seconds, then release
    }
}
