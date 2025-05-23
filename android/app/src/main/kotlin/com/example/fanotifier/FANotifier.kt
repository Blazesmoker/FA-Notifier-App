package com.blazesmoker.fanotifier

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngineGroup
import android.util.Log

class FANotifier : Application() {
    lateinit var engineGroup: FlutterEngineGroup

    override fun onCreate() {
        super.onCreate()
        Log.d("FANotifier", "🟢 Initializing FlutterEngineGroup...")
        engineGroup = FlutterEngineGroup(applicationContext)
    }

    fun createEngine(context: Context): FlutterEngineGroup.Options {
        Log.d("FANotifier", "🟢 Creating engine with PlatformViewsControllerFix...")
        return FlutterEngineGroup.Options(context)
            .setPlatformViewsController(PlatformViewsControllerFix(context))
    }
}