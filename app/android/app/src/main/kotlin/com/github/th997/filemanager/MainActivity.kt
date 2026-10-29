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
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            }
            else -> null
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
        if (uri.scheme == "file") {
            return uri.path
        }
        if (uri.scheme == "content") {
            try {
                var displayName: String? = null
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            displayName = cursor.getString(nameIndex)
                        }
                    }
                }
                if (displayName.isNullOrBlank()) {
                    displayName = "shared_file_${System.currentTimeMillis()}"
                }
                val inboxDir = File(cacheDir, "inbox")
                if (!inboxDir.exists()) {
                    inboxDir.mkdirs()
                }
                val destFile = File(inboxDir, displayName)
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(destFile).use { output ->
                        input.copyTo(output)
                    }
                }
                return destFile.absolutePath
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return null
    }
}
