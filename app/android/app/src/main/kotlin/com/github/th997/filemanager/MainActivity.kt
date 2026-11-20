package com.github.th997.filemanager

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val ACTION_OI_PICK_FILE = "org.openintents.action.PICK_FILE"
    }

    private var openFileChannel: MethodChannel? = null
    private var pendingFilePath: String? = null
    private var pendingPickRequest: Map<String, Any?>? = null
    private var pendingPickAction: String? = null
    private var pendingSharePaths: List<String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
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
                "getInitialPickRequest" -> {
                    val req = pendingPickRequest
                    pendingPickRequest = null
                    result.success(req)
                }
                "getInitialShareRequest" -> {
                    val paths = pendingSharePaths
                    pendingSharePaths = null
                    result.success(paths)
                }
                "completePickRequest" -> {
                    val rawPaths = call.argument<List<String>>("paths") ?: emptyList()
                    val ok = completePickResult(rawPaths)
                    result.success(ok)
                }
                "cancelPickRequest" -> {
                    pendingPickRequest = null
                    pendingPickAction = null
                    setResult(Activity.RESULT_CANCELED)
                    finish()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action

        // External file picker requests (ACTION_GET_CONTENT / ACTION_PICK /
        // ACTION_OPEN_DOCUMENT / OI PICK_FILE)
        if (action == Intent.ACTION_GET_CONTENT ||
            action == Intent.ACTION_PICK ||
            action == Intent.ACTION_OPEN_DOCUMENT ||
            action == ACTION_OI_PICK_FILE
        ) {
            val allowMultiple = intent.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            val mimeType = intent.type ?: "*/*"
            val extraMimeTypes = intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.toList() ?: emptyList()
            val req = mapOf<String, Any?>(
                "allowMultiple" to allowMultiple,
                "mimeType" to mimeType,
                "extraMimeTypes" to extraMimeTypes,
                "localOnly" to intent.getBooleanExtra(Intent.EXTRA_LOCAL_ONLY, false),
            )
            pendingPickRequest = req
            pendingPickAction = action
            // Clear the pending copy only once Dart acks delivery; if the Dart
            // handler is not up yet the invoke fails and getInitialPickRequest
            // must still find the request.
            openFileChannel?.invokeMethod("onPickRequest", req, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    pendingPickRequest = null
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

                override fun notImplemented() {}
            })
            return
        }

        // External share requests (ACTION_SEND / ACTION_SEND_MULTIPLE)
        if (action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE) {
            val uris = mutableListOf<Uri>()
            if (action == Intent.ACTION_SEND) {
                val streamUri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (streamUri != null) uris.add(streamUri)
            } else {
                val streamList = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (streamList != null) {
                    uris.addAll(streamList.filterNotNull())
                }
            }

            intent.clipData?.let { clipData ->
                for (i in 0 until clipData.itemCount) {
                    val itemUri = clipData.getItemAt(i)?.uri
                    if (itemUri != null && !uris.contains(itemUri)) {
                        uris.add(itemUri)
                    }
                }
            }
            if (uris.isEmpty() && intent.data != null) {
                uris.add(intent.data!!)
            }

            val resolvedPaths = mutableListOf<String>()
            for (u in uris) {
                val path = resolveUri(u)
                if (path != null && !resolvedPaths.contains(path)) {
                    resolvedPaths.add(path)
                }
            }

            if (resolvedPaths.isEmpty()) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrBlank()) {
                    try {
                        val inboxDir = File(cacheDir, "inbox")
                        if (!inboxDir.exists()) inboxDir.mkdirs()
                        val textFile = File(inboxDir, "shared_text_${System.currentTimeMillis()}.txt")
                        textFile.writeText(text)
                        resolvedPaths.add(textFile.absolutePath)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }

            if (resolvedPaths.isNotEmpty()) {
                pendingSharePaths = resolvedPaths
                openFileChannel?.invokeMethod("onShareReceived", mapOf("paths" to resolvedPaths), object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        pendingSharePaths = null
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                    override fun notImplemented() {}
                })
            }
            return
        }

        val uri: Uri? = intent.data ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
        if (uri != null) {
            val resolvedPath = resolveUri(uri)
            if (resolvedPath != null) {
                pendingFilePath = resolvedPath
                openFileChannel?.invokeMethod("onFileOpened", resolvedPath)
            }
        }
    }

    private fun completePickResult(paths: List<String>): Boolean {
        pendingPickRequest = null
        val action = pendingPickAction
        pendingPickAction = null
        val uris = mutableListOf<Uri>()
        for (rawPath in paths) {
            val file = File(rawPath)
            if (!file.exists() || !file.isFile) continue
            // Return FileProvider content URIs so any calling app can read the file
            val uri = try {
                FileProvider.getUriForFile(this, "$packageName.filepicker.provider", file)
            } catch (e: Exception) {
                e.printStackTrace()
                documentUriFor(file)
            }
            if (uri != null) uris.add(uri)
        }
        if (uris.isEmpty()) {
            setResult(Activity.RESULT_CANCELED)
            finish()
            return false
        }

        val resultIntent = Intent()
        resultIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (action == Intent.ACTION_OPEN_DOCUMENT) {
            resultIntent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        val caller = callingPackage
        if (caller != null) {
            for (uri in uris) {
                try {
                    grantUriPermission(
                        caller,
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        android.util.Log.d("FPPick", "pick result action=$action uris=$uris")
        if (uris.size == 1) {
            resultIntent.data = uris[0]
            resultIntent.clipData = ClipData.newRawUri("file", uris[0])
        } else {
            val clipData = ClipData.newRawUri("files", uris[0])
            for (i in 1 until uris.size) {
                clipData.addItem(ClipData.Item(uris[i]))
            }
            resultIntent.clipData = clipData
        }

        setResult(Activity.RESULT_OK, resultIntent)
        finish()
        return true
    }

    private fun documentUriFor(file: File): Uri? {
        val roots = listOf(
            "internal_storage" to Environment.getExternalStorageDirectory(),
            "app_files" to (getExternalFilesDir(null) ?: filesDir),
            "cache" to cacheDir,
            "external_cache" to externalCacheDir,
        )
        val canonical = file.canonicalFile.path
        for ((rootId, base) in roots) {
            val rootPath = base?.canonicalFile?.path ?: continue
            val prefix = rootPath + File.separator
            if (canonical.startsWith(prefix)) {
                val rel = canonical.substring(prefix.length)
                return DocumentsContract.buildDocumentUri("$packageName.documents", "$rootId:$rel")
            }
        }
        return null
    }

    private fun resolveExternalStorageDocumentPath(uri: Uri): String? {
        val docId = try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                DocumentsContract.getDocumentId(uri)
            } else {
                DocumentsContract.getTreeDocumentId(uri)
            }
        } catch (_: Exception) {
            null
        } ?: return null

        val authority = uri.authority
        if (authority == "com.android.externalstorage.documents") {
            val idx = docId.indexOf(':')
            if (idx > 0) {
                val volume = docId.substring(0, idx)
                val rel = docId.substring(idx + 1).trimStart('/')
                if (volume.equals("primary", ignoreCase = true)) {
                    return resolveContainedPath(Environment.getExternalStorageDirectory(), rel)
                } else {
                    // Secondary storage / SD card: /storage/<volume>/<rel>
                    val candidate = File("/storage/$volume", rel)
                    if (candidate.exists() && candidate.canRead()) {
                        return candidate.canonicalPath
                    }
                }
            }
        } else if (authority == "com.android.providers.downloads.documents") {
            try {
                if (docId.startsWith("raw:")) {
                    val rawFile = File(docId.removePrefix("raw:"))
                    if (rawFile.exists() && rawFile.canRead()) return rawFile.canonicalPath
                }
                val cleanId = docId.substringAfterLast(':')
                val idLong = cleanId.toLongOrNull()
                if (idLong != null) {
                    val contentUri = android.content.ContentUris.withAppendedId(
                        Uri.parse("content://downloads/public_downloads"),
                        idLong,
                    )
                    queryDataColumn(contentUri)?.let { return it }
                }
            } catch (_: Exception) {}
        } else if (authority == "com.android.providers.media.documents") {
            try {
                val split = docId.split(':')
                if (split.size >= 2) {
                    val type = split[0]
                    val id = split[1]
                    val baseUri = when (type) {
                        "image" -> android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        "video" -> android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        "audio" -> android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                        else -> android.provider.MediaStore.Files.getContentUri("external")
                    }
                    queryDataColumn(baseUri, "_id=?", arrayOf(id))?.let { return it }
                }
            } catch (_: Exception) {}
        } else if (authority == "$packageName.documents") {
            val idx = docId.indexOf(':')
            if (idx > 0) {
                val rootId = docId.substring(0, idx)
                val rel = docId.substring(idx + 1).trimStart('/')
                val base = when (rootId) {
                    "internal_storage" -> Environment.getExternalStorageDirectory()
                    "app_files" -> getExternalFilesDir(null) ?: filesDir
                    "cache" -> cacheDir
                    "external_cache" -> externalCacheDir
                    else -> null
                }
                return resolveContainedPath(base, rel)
            }
        }
        return null
    }

    private fun queryDataColumn(uri: Uri, selection: String? = null, selectionArgs: Array<String>? = null): String? {
        return try {
            contentResolver.query(uri, arrayOf("_data"), selection, selectionArgs, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex("_data")
                    if (idx != -1) {
                        val path = cursor.getString(idx)
                        if (!path.isNullOrBlank()) {
                            val f = File(path)
                            if (f.exists() && f.canRead()) f.canonicalPath else null
                        } else null
                    } else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    // docIds arrive from untrusted intents, so `..` segments must not escape
    // the volume root even when the escaped target happens to be readable.
    private fun resolveContainedPath(base: File?, rel: String): String? {
        if (base == null) return null
        val root = base.canonicalFile
        val candidate = if (rel.isEmpty()) root else File(root, rel).canonicalFile
        if (candidate.path != root.path &&
            !candidate.path.startsWith(root.path + File.separator)
        ) {
            return null
        }
        return if (candidate.exists() && candidate.canRead()) candidate.path else null
    }

    private fun resolveUri(uri: Uri): String? {
        val scheme = uri.scheme
        val inboxDir = File(cacheDir, "inbox")
        if (!inboxDir.exists()) {
            inboxDir.mkdirs()
        }

        // 1. Direct file:// scheme (works for both files and directories)
        if (scheme == "file") {
            val rawPath = uri.path
            if (!rawPath.isNullOrEmpty()) {
                val file = File(rawPath)
                if (file.exists() && file.canRead()) {
                    return file.absolutePath
                }
            }
        }

        // 2. Direct resolution for SAF / DocumentsProvider / MediaStore / FileProvider URIs
        if (scheme == "content") {
            // Check FileProvider-style paths that map directly to accessible storage
            val uriPath = uri.path
            if (!uriPath.isNullOrEmpty()) {
                val candidates = mutableListOf<String>()
                if (uriPath.startsWith("/root/")) {
                    candidates.add(uriPath.substring("/root".length))
                }
                if (uriPath.startsWith("/external_files/")) {
                    candidates.add(File(Environment.getExternalStorageDirectory(), uriPath.substring("/external_files/".length)).path)
                }
                candidates.add(uriPath)
                for (cand in candidates) {
                    val f = File(cand)
                    if (f.exists() && f.canRead()) {
                        return f.canonicalPath
                    }
                }
            }

            resolveExternalStorageDocumentPath(uri)?.let { return it }
            // Check if ContentProvider directly exposes physical path via _data
            queryDataColumn(uri)?.let { return it }
        }

        // 3. content:// scheme or file stream copy
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

            var destFile = File(inboxDir, displayName)
            if (destFile.exists()) {
                val nameWithoutExt = displayName.substringBeforeLast('.', displayName)
                val ext = if (displayName.contains('.')) "." + displayName.substringAfterLast('.') else ""
                var count = 1
                while (destFile.exists()) {
                    destFile = File(inboxDir, "${nameWithoutExt}_$count$ext")
                    count++
                }
            }
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
