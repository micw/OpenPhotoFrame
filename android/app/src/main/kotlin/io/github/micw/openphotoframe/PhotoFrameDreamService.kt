package io.github.micw.openphotoframe

import android.content.Intent
import android.service.dreams.DreamService

class PhotoFrameDreamService : DreamService() {
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()

        isInteractive = false
        isFullscreen = true

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("is_dream", true)
        }
        startActivity(intent)
        finish()
    }
}
