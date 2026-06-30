package io.github.micw.openphotoframe

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        @Volatile
        var isRunning = false
            private set
    }

    private lateinit var screenControlHandler: ScreenControlHandler
    private lateinit var keepAliveHandler: KeepAliveHandler
    private lateinit var updaterHandler: UpdaterHandler
    var isDreamMode = false
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        isDreamMode = intent?.getBooleanExtra("is_dream", false) ?: false
        Log.d("MainActivity", "isDreamMode: $isDreamMode")

        // Debug logging for screen size detection
        val display = windowManager.defaultDisplay
        val size = android.graphics.Point()
        display.getSize(size)
        Log.d("MainActivity", "Window size onCreate: ${size.x}x${size.y}")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        isDreamMode = intent.getBooleanExtra("is_dream", false)
        Log.d("MainActivity", "onNewIntent isDreamMode: $isDreamMode")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // Debug logging for screen size detection
            val display = windowManager.defaultDisplay
            val size = android.graphics.Point()
            display.getSize(size)
            Log.d("MainActivity", "Window size onFocus: ${size.x}x${size.y}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        screenControlHandler = ScreenControlHandler(this)
        screenControlHandler.configureChannel(flutterEngine)
        
        keepAliveHandler = KeepAliveHandler(this)
        keepAliveHandler.configureChannel(flutterEngine)

        updaterHandler = UpdaterHandler(this)
        updaterHandler.configureChannel(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        isRunning = true
    }

    override fun onStop() {
        super.onStop()
        isRunning = false
    }
}
