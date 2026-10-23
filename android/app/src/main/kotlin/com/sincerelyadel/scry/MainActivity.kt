package com.sincerelyadel.scry

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The in-app browser's cookies for a site, including the ones its
        // scripts can't see. Used after passing ranobes.net's human check.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scry/cookies")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> {
                        val manager = CookieManager.getInstance()
                        manager.flush()
                        result.success(manager.getCookie(call.argument<String>("url")))
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
