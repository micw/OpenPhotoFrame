package io.github.micw.openphotoframe

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var screenControlHandler: ScreenControlHandler
    private lateinit var keepAliveHandler: KeepAliveHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Debug logging for screen size detection
        val display = windowManager.defaultDisplay
        val size = android.graphics.Point()
        display.getSize(size)
        Log.d("MainActivity", "Window size onCreate: ${size.x}x${size.y}")
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
    }
}
