package com.follow.clash

import android.content.Context
import com.follow.clash.common.GlobalState

class StartupCheckpointPreferences(context: Context) : StartupCheckpointStore {
    private val preferences = context.getSharedPreferences("elephant_startup", Context.MODE_PRIVATE)

    override fun read(): StartupCheckpoint? = runCatching {
        val value = preferences.getString("checkpoint", null) ?: return@runCatching null
        val parts = value.split('|')
        require(parts.size == 3)
        StartupCheckpoint(parts[0], StartupPhase.valueOf(parts[1]), parts[2].toLong())
    }.getOrNull()

    override fun write(checkpoint: StartupCheckpoint) {
        val value = "${checkpoint.attempt}|${checkpoint.phase.name}|${checkpoint.timeMillis}"
        runCatching {
            check(preferences.edit().putString("checkpoint", value).commit())
        }.onFailure { GlobalState.log("Unable to persist startup checkpoint") }
    }
}
