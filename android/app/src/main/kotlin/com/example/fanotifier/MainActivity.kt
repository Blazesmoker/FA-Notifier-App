package com.blazesmoker.fanotifier

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // If you have a custom engine group, keep your references:
    private var customEngine: FlutterEngine? = null
    private val CHANNEL = "com.blazesmoker.fanotifier/icon"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // By default, we do nothing here for the icon switching.
        Log.d("MainActivity", "🟢 Activity created")
        Log.d("MainActivity", "🟢 onCreate => default static icon is in use.")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "🟢 Configuring engine: ${flutterEngine.hashCode()}")
        // Apply jitter fix for platform views
        PlatformViewsHandlerFix.fix(flutterEngine.platformViewsController)

        // Listen for "switchIcon" calls from Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
        customEngine?.destroy()
        super.onDestroy()
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
}
