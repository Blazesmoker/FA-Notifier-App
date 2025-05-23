package com.blazesmoker.fanotifier

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import android.view.MotionEvent
import io.flutter.embedding.engine.systemchannels.PlatformViewsChannel
import io.flutter.plugin.platform.PlatformViewsController

class PlatformViewsControllerFix(context: Context) : PlatformViewsController() {
    init {
        Log.d("PlatformFix", "✅ Custom controller initialized! Context: ${context.applicationContext}")
    }

    @SuppressLint("VisibleForTests")
    override fun toMotionEvent(
        density: Float,
        touch: PlatformViewsChannel.PlatformViewTouch?,
        usingVirtualDisplay: Boolean
    ): MotionEvent {
        val event = super.toMotionEvent(density, touch, usingVirtualDisplay)
        event.source = 0x5002 // SOURCE_TOUCHSCREEN
        Log.d("PlatformFix", "Fixed MotionEvent source: ${event.source}")
        return event
    }
}