package com.follow.clash

import android.app.Application
import android.content.Context
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch

class FlClashApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        GlobalState.launch { ServiceState.recoverStartup() }
    }

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
