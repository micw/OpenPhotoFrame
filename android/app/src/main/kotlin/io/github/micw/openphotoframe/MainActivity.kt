package io.github.micw.openphotoframe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var screenControlHandler: ScreenControlHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        screenControlHandler = ScreenControlHandler(this)
        screenControlHandler.configureChannel(flutterEngine)
    }
}
