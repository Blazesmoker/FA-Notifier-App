package com.blazesmoker.fanotifier

import android.util.Log
import android.util.SparseArray
import io.flutter.embedding.android.AndroidTouchProcessor
import io.flutter.embedding.engine.systemchannels.PlatformViewsChannel
import io.flutter.plugin.platform.PlatformViewsController
import java.lang.reflect.Field
import java.lang.reflect.Method

/**
 * Fix Android PlatformViewWrapper: prevents extra offset translation for touch events.
 * Issue: https://github.com/flutter/flutter/issues/135531
 */
class PlatformViewsHandlerFix(private val platformViewsController: PlatformViewsController) :
    PlatformViewsChannel.PlatformViewsHandler {

    companion object {
        fun fix(platformViewsController: PlatformViewsController) {
            PlatformViewsHandlerFix(platformViewsController).replaceHandler()
        }
    }

    private lateinit var origin: PlatformViewsChannel.PlatformViewsHandler
    private var viewWrappers: SparseArray<*>? = null
    private var setTouchProcessorMethod: Method? = null

    override fun createForPlatformViewLayer(request: PlatformViewsChannel.PlatformViewCreationRequest) {
        origin.createForPlatformViewLayer(request)
    }

    override fun createForTextureLayer(request: PlatformViewsChannel.PlatformViewCreationRequest): Long {
        val result = origin.createForTextureLayer(request)
        removeTouchProcessor(request.viewId)
        return result
    }

    override fun dispose(viewId: Int) {
        origin.dispose(viewId)
    }

    override fun resize(
        request: PlatformViewsChannel.PlatformViewResizeRequest,
        onComplete: PlatformViewsChannel.PlatformViewBufferResized
    ) {
        origin.resize(request, onComplete)
    }

    override fun offset(viewId: Int, top: Double, left: Double) {
        origin.offset(viewId, top, left)
    }

    override fun onTouch(touch: PlatformViewsChannel.PlatformViewTouch) {
        origin.onTouch(touch)
    }

    override fun setDirection(viewId: Int, direction: Int) {
        origin.setDirection(viewId, direction)
    }

    override fun clearFocus(viewId: Int) {
        origin.clearFocus(viewId)
    }

    override fun synchronizeToNativeViewHierarchy(yes: Boolean) {
        origin.synchronizeToNativeViewHierarchy(yes)
    }

    private fun replaceHandler() {
        try {
            val handlerField: Field = PlatformViewsController::class.java.getDeclaredField("channelHandler")
            handlerField.isAccessible = true
            val originHandler = handlerField.get(platformViewsController) as? PlatformViewsChannel.PlatformViewsHandler
            if (originHandler is PlatformViewsHandlerFix) {
                Log.d("PlatformViewsHandlerFix", "Handler already replaced")
                return
            }
            origin = originHandler ?: return
            handlerField.set(platformViewsController, this)
            Log.d("PlatformViewsHandlerFix", "Successfully replaced channelHandler")
        } catch (e: Exception) {
            Log.e("PlatformViewsHandlerFix", "Failed to replace channelHandler", e)
        }
    }

    private fun removeTouchProcessor(viewId: Int) {
        try {
            val wrappers = getViewWrappers() ?: return
            val platformViewWrapper = wrappers.get(viewId) ?: return
            val method = getSetTouchProcessorMethod(platformViewWrapper)
            method?.invoke(platformViewWrapper, null)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getViewWrappers(): SparseArray<*>? {
        if (viewWrappers == null) {
            try {
                val field: Field = PlatformViewsController::class.java.getDeclaredField("viewWrappers")
                field.isAccessible = true
                viewWrappers = field.get(platformViewsController) as SparseArray<*>
            } catch (e: Exception) {
                Log.e("PlatformViewsHandlerFix", "Failed to get viewWrappers", e)
            }
        }
        return viewWrappers
    }

    private fun getSetTouchProcessorMethod(platformViewWrapper: Any): Method? {
        if (setTouchProcessorMethod == null) {
            try {
                setTouchProcessorMethod = platformViewWrapper.javaClass.getDeclaredMethod(
                    "setTouchProcessor",
                    AndroidTouchProcessor::class.java
                )
                setTouchProcessorMethod?.isAccessible = true
            } catch (e: Exception) {
                Log.e("PlatformViewsHandlerFix", "Failed to get setTouchProcessorMethod", e)
            }
        }
        return setTouchProcessorMethod
    }
}
