package com.example.gtex_collab_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val SAVE_CHANNEL = "gtex_collab_app/file_save"
        private const val SAVE_REQUEST_CODE = 5123
    }

    // Android may restore its system bars after document pickers and other
    // native windows. Reapply the same transient-by-swipe immersive behavior.
    @Suppress("DEPRECATION")
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsets.Type.navigationBars())
            }
        } else {
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )
        }
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingSource: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveDownloadedFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("SAVE_IN_PROGRESS", "Another save is already open", null)
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("path")
                val suggestedName = call.argument<String>("name")
                    ?.replace(Regex("[\\\\/]"), "_")
                    ?.ifBlank { "download" } ?: "download"
                if (sourcePath.isNullOrBlank() || !File(sourcePath).isFile) {
                    result.error("FILE_MISSING", "Temporary download was not found", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                pendingSource = sourcePath
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    startActivityForResult(intent, SAVE_REQUEST_CODE)
                } catch (error: Exception) {
                    pendingResult = null
                    pendingSource = null
                    result.error("SAVE_FAILED", error.message, null)
                }
            }
    }

    @Deprecated("Deprecated in Android framework but required for SAF callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_REQUEST_CODE) return
        val result = pendingResult ?: return
        val source = pendingSource
        pendingResult = null
        pendingSource = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(false)
            return
        }
        try {
            val uri = data.data!!
            val output = contentResolver.openOutputStream(uri)
                ?: throw IllegalStateException("Unable to open selected destination")
            FileInputStream(File(source!!)).use { input ->
                output.use { destination -> input.copyTo(destination) }
            }
            result.success(true)
        } catch (error: Exception) {
            result.error("SAVE_FAILED", error.message, null)
        }
    }
}
