package com.blazesmoker.fanotifier

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var customEngine: FlutterEngine? = null
    private val iconChannel = "com.blazesmoker.fanotifier/icon"
    private val settingsChannel = "com.blazesmoker.fanotifier/settings"
    private val translationChannel = "app.translation"
    private val imeAnimationChannel = "app.ime_animation"
    private var imeEventSink: EventChannel.EventSink? = null
    private var latestImeBottom = 0.0
    private var imeAnimationActive = false
    private var imeAnimationClosing = false
    private var imeWasVisibleBeforeAnimation = false
    private var imeAnimationStartBottom = 0.0
    private var imeAnimationEndBottom = 0.0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        attachImeAnimationCallback()

        Log.d("MainActivity", "🟢 Activity created")
        Log.d("MainActivity", "🟢 onCreate => default static icon is in use.")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "🟢 Configuring engine: ${flutterEngine.hashCode()}")
        // Apply jitter fix for platform views
        // uncomment to apply webview slow scroll fix for flutter 3.35.4
        PlatformViewsHandlerFix.fix(flutterEngine.platformViewsController)

        // Listen for "switchIcon" calls from Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "switchIcon" -> {
                        val useAdaptive = call.argument<Boolean>("useAdaptive") ?: false
                        switchAppIcon(useAdaptive)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                addCategory(Intent.CATEGORY_DEFAULT)
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, translationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "translation.showProcessText" -> {
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        result.success(showProcessTextTranslation(text))
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, imeAnimationChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    imeEventSink = events
                    publishImeAnimationFrame(
                        ViewCompat.getRootWindowInsets(window.decorView)
                    )
                }

                override fun onCancel(arguments: Any?) {
                    imeEventSink = null
                }
            })
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val fanotifier = context.applicationContext as FANotifier
        val options = fanotifier.createEngine(context)
        customEngine = fanotifier.engineGroup.createAndRunEngine(options)
        // Re-apply jitter fix to this custom engine
        customEngine?.platformViewsController?.let {
            PlatformViewsHandlerFix.fix(it)
            Log.d("MainActivity", "🟢 Applied PlatformViewsHandlerFix to customEngine")
        }
        return customEngine
    }

    override fun onDestroy() {
        imeEventSink = null
        customEngine?.destroy()
        super.onDestroy()
    }

    private fun attachImeAnimationCallback() {
        val rootView = window.decorView
        ViewCompat.setWindowInsetsAnimationCallback(
            rootView,
            object : WindowInsetsAnimationCompat.Callback(
                DISPATCH_MODE_CONTINUE_ON_SUBTREE
            ) {
                override fun onPrepare(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() == 0) {
                        return
                    }

                    val insets = ViewCompat.getRootWindowInsets(rootView)
                    imeAnimationActive = true
                    imeAnimationClosing = false
                    imeWasVisibleBeforeAnimation =
                        insets?.isVisible(WindowInsetsCompat.Type.ime()) == true
                    publishImeAnimationFrame(insets)
                    imeAnimationStartBottom = latestImeBottom
                    imeAnimationEndBottom = latestImeBottom
                }

                override fun onStart(
                    animation: WindowInsetsAnimationCompat,
                    bounds: WindowInsetsAnimationCompat.BoundsCompat
                ): WindowInsetsAnimationCompat.BoundsCompat {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() != 0) {
                        val targetInsets =
                            ViewCompat.getRootWindowInsets(rootView)
                        val targetVisible = targetInsets?.isVisible(
                            WindowInsetsCompat.Type.ime()
                        ) ?: !imeWasVisibleBeforeAnimation
                        imeAnimationClosing =
                            imeWasVisibleBeforeAnimation && !targetVisible
                        val density = resources.displayMetrics.density.toDouble()
                        imeAnimationEndBottom = if (targetVisible) {
                            targetInsets?.let { imeBottom(it) }
                                ?: (bounds.upperBound.bottom / density)
                        } else {
                            bounds.lowerBound.bottom / density
                        }
                        publishImeAnimationFrame(null)
                    }
                    return bounds
                }

                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: MutableList<WindowInsetsAnimationCompat>
                ): WindowInsetsCompat {
                    val imeAnimation = runningAnimations.firstOrNull {
                        it.typeMask and WindowInsetsCompat.Type.ime() != 0
                    }
                    if (imeAnimation != null) {
                        latestImeBottom = imeAnimationStartBottom +
                            ((imeAnimationEndBottom - imeAnimationStartBottom) *
                                imeAnimation.interpolatedFraction.toDouble())
                        publishImeAnimationFrame(null)
                    }
                    return insets
                }

                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() == 0) {
                        return
                    }

                    imeAnimationActive = false
                    imeAnimationClosing = false
                    imeWasVisibleBeforeAnimation = false
                    publishImeAnimationFrame(
                        ViewCompat.getRootWindowInsets(rootView)
                    )
                }
            }
        )
        ViewCompat.requestApplyInsets(rootView)
    }

    private fun publishImeAnimationFrame(insets: WindowInsetsCompat?) {
        if (insets != null) {
            latestImeBottom = imeBottom(insets)
        }
        imeEventSink?.success(
            mapOf(
                "bottom" to latestImeBottom,
                "isAnimating" to imeAnimationActive,
                "isClosing" to imeAnimationClosing
            )
        )
    }

    private fun imeBottom(insets: WindowInsetsCompat): Double {
        return insets.getInsets(WindowInsetsCompat.Type.ime()).bottom /
            resources.displayMetrics.density.toDouble()
    }


    private fun switchAppIcon(useAdaptive: Boolean) {
        val pm = packageManager

        // Real main activity => static PNG
        val main = ComponentName(packageName, "com.blazesmoker.fanotifier.MainActivity")
        // Alias => adaptive icon
        val adaptive = ComponentName(packageName, "com.blazesmoker.fanotifier.AdaptiveAlias")

        if (useAdaptive) {
            pm.setComponentEnabledSetting(
                main,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            pm.setComponentEnabledSetting(
                adaptive,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.d("MainActivity", "🟢 Switched to Adaptive Icon.")
        } else {
            pm.setComponentEnabledSetting(
                main,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            pm.setComponentEnabledSetting(
                adaptive,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.d("MainActivity", "🟢 Switched to Static Icon.")
        }

        Handler(Looper.getMainLooper()).postDelayed({
            val intent = pm.getLaunchIntentForPackage(packageName)
            intent?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            finishAffinity()
        }, 4000)
    }

    private fun showProcessTextTranslation(text: String): Boolean {
        if (text.isEmpty()) {
            return false
        }

        return try {
            val processTextIntent = Intent(Intent.ACTION_PROCESS_TEXT).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_PROCESS_TEXT, text)
                putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
            }
            val activities = packageManager.queryIntentActivities(
                processTextIntent,
                PackageManager.MATCH_DEFAULT_ONLY
            )
            val translateActivity = activities.firstOrNull {
                it.activityInfo.packageName == "com.google.android.apps.translate"
            } ?: activities.firstOrNull {
                it.activityInfo.packageName.contains("translate", ignoreCase = true)
            } ?: return false

            processTextIntent.setClassName(
                translateActivity.activityInfo.packageName,
                translateActivity.activityInfo.name
            )
            startActivity(processTextIntent)
            true
        } catch (error: Exception) {
            Log.w("MainActivity", "PROCESS_TEXT translation failed", error)
            false
        }
    }

}
