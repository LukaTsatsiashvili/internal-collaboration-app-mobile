package com.example.gtex_collab_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.Locale

/**
 * Save public Drive downloads in Downloads/GTEX Collaboration (Android 10+).
 * The saved MediaStore URI is opened with a read grant; no broad file access
 * permission or private sandbox download path is necessary.
 */
class DriveDownloadHandler(private val activity: Activity) {
    companion object {
        const val CHANNEL = "gtex_collab_app/drive_download"
        private const val LEGACY_REQUEST = 5124
        private const val SUBDIRECTORY = "GTEX Collaboration"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingFile: File? = null
    private var pendingMime: String = "application/octet-stream"

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveAndOpen") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val name = safeName(call.argument<String>("name") ?: "download")
        val source = path?.let(::File)
        if (source == null || !source.isFile) {
            result.error("FILE_MISSING", "Downloaded temporary file is missing", null)
            return
        }
        if (pendingResult != null) {
            result.error("DOWNLOAD_BUSY", "Another download is being saved", null)
            return
        }

        val mime = mimeFor(name)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Avoid blocking Flutter's Android UI thread for large workbooks.
            Thread {
                try {
                    val uri = saveToMediaStore(source, name, mime)
                    activity.runOnUiThread {
                        result.success(mapOf(
                            "saved" to true,
                            "opened" to openViewer(uri, mime),
                        ))
                    }
                } catch (error: Exception) {
                    activity.runOnUiThread {
                        result.error("DOWNLOAD_SAVE_FAILED", error.message, null)
                    }
                }
            }.start()
            return
        }

        // Older Android: SAF avoids requesting legacy broad storage access.
        pendingResult = result
        pendingFile = source
        pendingMime = mime
        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_TITLE, name)
            }
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, LEGACY_REQUEST)
        } catch (error: Exception) {
            clearPending()
            result.error("DOWNLOAD_SAVE_FAILED", error.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != LEGACY_REQUEST) return false
        val result = pendingResult
        val source = pendingFile
        val mime = pendingMime
        clearPending()
        if (result == null) return true

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(mapOf("saved" to false, "opened" to false))
            return true
        }
        try {
            val uri = data.data!!
            if (source == null || !source.isFile) {
                throw IllegalStateException("Temporary file is no longer available")
            }
            val output = activity.contentResolver.openOutputStream(uri)
                ?: throw IllegalStateException("Could not write the chosen file")
            FileInputStream(source).use { input ->
                output.use { input.copyTo(it) }
            }
            result.success(mapOf(
                "saved" to true,
                "opened" to openViewer(uri, mime),
            ))
        } catch (error: Exception) {
            result.error("DOWNLOAD_SAVE_FAILED", error.message, null)
        }
        return true
    }

    private fun clearPending() {
        pendingResult = null
        pendingFile = null
        pendingMime = "application/octet-stream"
    }

    private fun safeName(input: String): String {
        val cleaned = input.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1f]"), "_").trim()
        return cleaned.ifEmpty { "download" }.take(200)
    }

    private fun mimeFor(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return when (extension) {
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "xls" -> "application/vnd.ms-excel"
            "xlsm" -> "application/vnd.ms-excel.sheet.macroEnabled.12"
            "pdf" -> "application/pdf"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "doc" -> "application/msword"
            "csv" -> "text/csv"
            "txt" -> "text/plain"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "zip" -> "application/zip"
            else -> MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun saveToMediaStore(source: File, filename: String, mime: String): Uri {
        val resolver = activity.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$SUBDIRECTORY/"
        val name = uniqueName(filename, relativePath)

        val metadata = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, metadata)
            ?: throw IllegalStateException("Cannot create Downloads entry")
        try {
            val output = resolver.openOutputStream(uri)
                ?: throw IllegalStateException("Cannot write Downloads entry")
            FileInputStream(source).use { input ->
                output.use { input.copyTo(it) }
            }
            val completed = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, completed, null, null)
            return uri
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun uniqueName(filename: String, relativePath: String): String {
        val dot = filename.lastIndexOf('.')
        val stem = if (dot > 0) filename.substring(0, dot) else filename
        val extension = if (dot > 0) filename.substring(dot) else ""
        var candidate = filename
        var suffix = 2
        while (exists(candidate, relativePath)) {
            candidate = "$stem ($suffix)$extension"
            suffix++
        }
        return candidate
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun exists(name: String, relativePath: String): Boolean {
        // Some vendors restrict querying Downloads entries; writing a new
        // file should still work even when duplicate-name inspection fails.
        return try {
            activity.contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                arrayOf(name, relativePath),
                null,
            )?.use { cursor -> cursor.moveToFirst() } ?: false
        } catch (_: SecurityException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun openViewer(uri: Uri, mime: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
