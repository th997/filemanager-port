package com.github.th997.filemanager

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var openFileChannel: MethodChannel? = null
    private var pendingFilePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.github.th997.filemanager/open_file")
        openFileChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    val file = pendingFilePath
                    pendingFilePath = null
                    result.success(file)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val uri: Uri? = when (action) {
            Intent.ACTION_VIEW -> {
                intent.data ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            }
            Intent.ACTION_SEND -> {
                val streamUri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                streamUri ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri ?: intent.data
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val streamList = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                streamList?.firstOrNull() ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            }
            else -> intent.data ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
        }
        if (uri != null) {
            val resolvedPath = resolveUri(uri)
            if (resolvedPath != null) {
                pendingFilePath = resolvedPath
                openFileChannel?.invokeMethod("onFileOpened", resolvedPath)
            }
        }
    }

    private fun resolveUri(uri: Uri): String? {
        val scheme = uri.scheme
        val inboxDir = File(cacheDir, "inbox")
        if (!inboxDir.exists()) {
            inboxDir.mkdirs()
        }

        // 1. Direct file:// scheme
        if (scheme == "file") {
            val rawPath = uri.path
            if (!rawPath.isNullOrEmpty()) {
                val file = File(rawPath)
                if (file.exists() && file.canRead()) {
                    return file.absolutePath
                }
            }
        }

        // 2. content:// scheme or file stream copy
        try {
            var displayName: String? = null
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            displayName = cursor.getString(nameIndex)
                        }
                    }
                }
            } catch (_: Exception) {
                // Ignore query exceptions; some providers deny query permission but allow openInputStream
            }

            if (displayName.isNullOrBlank()) {
                val lastSeg = uri.lastPathSegment
                displayName = if (!lastSeg.isNullOrBlank()) {
                    lastSeg.substringAfterLast('/')
                } else {
                    "shared_${System.currentTimeMillis()}"
                }
            }
            // Sanitize file name to avoid directory traversal
            displayName = File(displayName).name.ifBlank { "shared_${System.currentTimeMillis()}" }

            val destFile = File(inboxDir, displayName)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            }
            if (destFile.exists() && destFile.length() > 0) {
                return destFile.absolutePath
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return null
    }
}
