package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StartupJournalTest {
    private class Store : StartupCheckpointStore {
        var value: StartupCheckpoint? = null
        override fun read() = value
        override fun write(checkpoint: StartupCheckpoint) { value = checkpoint }
    }

    @Test
    fun recoversEachInterruptedStageOnceAfterRestart() {
        for (phase in listOf(StartupPhase.PREFERENCES, StartupPhase.CONFIGURATION, StartupPhase.NOTIFICATION_PERMISSION, StartupPhase.VPN_PERMISSION, StartupPhase.SERVICE_BINDING, StartupPhase.CORE_START, StartupPhase.STOPPING)) {
            val store = Store()
            StartupJournal(store) { 100 }.begin("old", phase)
            val restarted = StartupJournal(store) { 200 }
            assertEquals(phase, restarted.recover()?.phase)
            assertEquals(StartupPhase.INTERRUPTED, store.value?.phase)
            assertEquals(200L, store.value?.timeMillis)
            assertNull(restarted.recover())
            restarted.begin("retry", StartupPhase.PREFERENCES)
            restarted.mark("retry", StartupPhase.CONFIGURATION)
            restarted.mark("retry", StartupPhase.STARTED)
            assertEquals(StartupPhase.STARTED, store.value?.phase)
            assertNull(StartupJournal(store).recover())
        }
    }

    @Test
    fun lateStartCannotOverwriteNewerStop() {
        val store = Store()
        val journal = StartupJournal(store)
        journal.begin("start", StartupPhase.SERVICE_BINDING)
        journal.begin("stop", StartupPhase.STOPPING)
        journal.mark("start", StartupPhase.STARTED)
        assertEquals(StartupPhase.STOPPING, store.value?.phase)
        journal.mark("stop", StartupPhase.STOPPED)
        journal.mark("stop", StartupPhase.CORE_START)
        assertEquals(StartupPhase.STOPPED, store.value?.phase)
    }

    @Test
    fun failedConfigurationDoesNotResumeOrEraseTheNextAttempt() {
        val store = Store()
        val journal = StartupJournal(store)
        journal.begin("bad", StartupPhase.CONFIGURATION)
        journal.mark("bad", StartupPhase.FAILED)
        assertNull(StartupJournal(store).recover())
        journal.begin("new", StartupPhase.VPN_PERMISSION)
        journal.mark("bad", StartupPhase.FAILED)
        assertEquals("new", store.value?.attempt)
        assertEquals(StartupPhase.VPN_PERMISSION, store.value?.phase)
        journal.mark("new", StartupPhase.STARTED)
        journal.begin("new", StartupPhase.PREFERENCES)
        assertEquals(StartupPhase.STARTED, store.value?.phase)
    }
}
