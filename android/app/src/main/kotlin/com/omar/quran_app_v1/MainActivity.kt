package com.omar.quran_app_v1

import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Extends AudioServiceActivity, NOT FlutterActivity.
///
/// just_audio_background requires it: its README says the activity must
/// be com.ryanheise.audioservice.AudioServiceActivity, or a custom
/// activity must subclass it, because the playback service and the
/// activity have to share one Flutter engine. On FlutterActivity every
/// attempt to set an audio source fails, which the app could only
/// report as "check your internet connection" — even with a perfectly
/// good connection. iOS has no equivalent requirement, which is why
/// recitation always worked there.
class MainActivity : AudioServiceActivity() {
    private val screenAwakeChannel = "com.omar.quran_app_v1/screen_awake"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenAwakeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Keeps the display on at full brightness while a
                    // Mushaf/reader screen is open — the system's own
                    // stay-awake flag, so no brightness is overridden.
                    "setKeepAwake" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
