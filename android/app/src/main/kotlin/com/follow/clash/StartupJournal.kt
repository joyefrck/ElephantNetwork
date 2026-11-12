package com.follow.clash

enum class StartupPhase {
    PREFERENCES,
    NOTIFICATION_PERMISSION,
    CONFIGURATION,
    VPN_PERMISSION,
    SERVICE_BINDING,
    CORE_START,
    STARTED,
    STOPPING,
    STOPPED,
    FAILED,
    INTERRUPTED,
}

data class StartupCheckpoint(val attempt: String, val phase: StartupPhase, val timeMillis: Long)

interface StartupCheckpointStore {
    fun read(): StartupCheckpoint?
    fun write(checkpoint: StartupCheckpoint)
}

class StartupJournal(private val store: StartupCheckpointStore, private val clock: () -> Long = System::currentTimeMillis) {
    @Synchronized
    fun recover(): StartupCheckpoint? {
        val checkpoint = store.read() ?: return null
        if (checkpoint.phase in terminalPhases) return null
        store.write(checkpoint.copy(phase = StartupPhase.INTERRUPTED, timeMillis = clock()))
        return checkpoint
    }

    @Synchronized
    fun begin(attempt: String, phase: StartupPhase) {
        if (store.read()?.attempt == attempt) return
        store.write(StartupCheckpoint(attempt, phase, clock()))
    }

    @Synchronized
    fun mark(attempt: String, phase: StartupPhase) {
        val current = store.read() ?: return
        if (current.attempt != attempt || current.phase in terminalPhases) return
        store.write(current.copy(phase = phase, timeMillis = clock()))
    }

    private companion object {
        val terminalPhases = setOf(StartupPhase.STARTED, StartupPhase.STOPPED, StartupPhase.FAILED, StartupPhase.INTERRUPTED)
    }
}
