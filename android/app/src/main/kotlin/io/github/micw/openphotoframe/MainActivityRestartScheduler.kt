package io.github.micw.openphotoframe

interface DelayedExecutor {
    fun postDelayed(runnable: Runnable, delayMillis: Long)

    fun removeCallbacks(runnable: Runnable)
}

class HandlerDelayedExecutor(
    private val handler: android.os.Handler,
) : DelayedExecutor {
    override fun postDelayed(runnable: Runnable, delayMillis: Long) {
        handler.postDelayed(runnable, delayMillis)
    }

    override fun removeCallbacks(runnable: Runnable) {
        handler.removeCallbacks(runnable)
    }
}

class MainActivityRestartScheduler(
    private val delayedExecutor: DelayedExecutor,
    private val restartDelayMs: Long,
    private val restartAction: () -> Unit,
) {
    private val restartRunnable = Runnable {
        restartAction()
    }

    fun schedule() {
        delayedExecutor.removeCallbacks(restartRunnable)
        delayedExecutor.postDelayed(restartRunnable, restartDelayMs)
    }

    fun cancel() {
        delayedExecutor.removeCallbacks(restartRunnable)
    }
}