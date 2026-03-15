package io.github.micw.openphotoframe

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class MainActivityRestartSchedulerTest {
    @Test
    fun cancelPreventsScheduledRestartExecution() {
        val executor = RecordingDelayedExecutor()
        var restartCount = 0
        val scheduler = MainActivityRestartScheduler(
            delayedExecutor = executor,
            restartDelayMs = 2_000L,
            restartAction = { restartCount++ },
        )

        scheduler.schedule()
        scheduler.cancel()
        executor.runPending()

        assertEquals(0, restartCount)
    }

    @Test
    fun scheduleRegistersRestartWithExpectedDelay() {
        val executor = RecordingDelayedExecutor()
        val scheduler = MainActivityRestartScheduler(
            delayedExecutor = executor,
            restartDelayMs = 2_000L,
            restartAction = {},
        )

        scheduler.schedule()

        assertNotNull(executor.pendingRunnable)
        assertEquals(2_000L, executor.lastDelayMillis)
    }
}

private class RecordingDelayedExecutor : DelayedExecutor {
    var pendingRunnable: Runnable? = null
    var lastDelayMillis: Long? = null

    override fun postDelayed(runnable: Runnable, delayMillis: Long) {
        pendingRunnable = runnable
        lastDelayMillis = delayMillis
    }

    override fun removeCallbacks(runnable: Runnable) {
        if (pendingRunnable == runnable) {
            pendingRunnable = null
        }
    }

    fun runPending() {
        val runnable = pendingRunnable
        pendingRunnable = null
        runnable?.run()
    }
}