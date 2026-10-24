package com.sincerelyadel.scry

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// Waiting for the person to choose a book file.
    private var pendingPick: MethodChannel.Result? = null

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
        // Lets the person choose an EPUB file and hands back its bytes.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scry/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickBook" -> pickBook(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickBook(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            // Some file apps don't know the EPUB type, so allow any file too.
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/epub+zip", "application/octet-stream", "*/*"),
            )
        }
        try {
            startActivityForResult(intent, PICK_BOOK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("unavailable", "No app to choose files with", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_BOOK) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val main = Handler(Looper.getMainLooper())
        // Books can be large; read off the main thread.
        Thread {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                main.post { result.success(bytes) }
            } catch (e: Exception) {
                main.post { result.error("read", "Couldn't read the file", null) }
            }
        }.start()
    }

    companion object {
        private const val PICK_BOOK = 4711
    }
}
