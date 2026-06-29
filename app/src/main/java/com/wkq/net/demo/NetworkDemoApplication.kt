package com.wkq.net.demo

import android.app.Application
import com.wkq.net.config.NetConfig
import com.wkq.net.core.NetManager

class NetworkDemoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NetManager.tryInit(
            NetConfig.Builder()
                .setBaseUrl("https://jsonplaceholder.typicode.com/")
                .setDebugLogsEnabled(true)
                .addDefaultHeader("Accept", "application/json")
                .build()
        )
    }
}
