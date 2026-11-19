package com.github.th997.filemanager

import android.database.Cursor
import android.database.MatrixCursor
import android.os.Build
import android.os.CancellationSignal
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.ArrayDeque
import java.util.Locale

/**
 * Storage Access Framework (SAF) DocumentsProvider that registers FP File Manager
 * as a browsable storage source inside Android's system file picker (DocumentsUI).
 */
class FileManagerDocumentsProvider : DocumentsProvider() {
    companion object {
        private const val ROOT_ID_INTERNAL = "internal_storage"
        private const val ROOT_ID_APP_FILES = "app_files"
        private const val ROOT_ID_CACHE = "cache"
        private const val ROOT_ID_EXTERNAL_CACHE = "external_cache"
        private const val ROOT_ID_BOOKMARKS = "bookmarks"
        private const val ROOT_PREFIX_REMOTE = "remote_"
        private const val MAX_SEARCH_RESULTS = 50
        private const val MAX_SEARCH_VISITED = 2000

        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_AVAILABLE_BYTES,
        )

        private val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
        )
    }

    override fun onCreate(): Boolean {
        pruneSafCache()
        return true
    }

    private fun pruneSafCache() {
        val ctx = context ?: return
        val cutoff = System.currentTimeMillis() - 3_600_000
        File(ctx.cacheDir, "saf_remote")
            .walkTopDown()
            .filter { it.isFile && it.lastModified() < cutoff }
            .forEach { it.delete() }
    }

    private fun getInternalStorageRootDir(): File? {
        val dir = Environment.getExternalStorageDirectory() ?: return null
        val hasAccess = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager() || dir.canRead()
        } else {
            dir.canRead()
        }
        return if (hasAccess && dir.exists() && dir.isDirectory) dir else null
    }

    private fun getAppFilesRootDir(): File? {
        val ctx = context ?: return null
        val dir = ctx.getExternalFilesDir(null) ?: ctx.filesDir
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return if (dir.exists() && dir.isDirectory) dir else null
    }

    private fun resolveRootDir(rootId: String): File {
        val dir = when (rootId) {
            ROOT_ID_INTERNAL -> getInternalStorageRootDir()
            ROOT_ID_APP_FILES -> getAppFilesRootDir()
            ROOT_ID_CACHE -> context?.cacheDir
            ROOT_ID_EXTERNAL_CACHE -> context?.externalCacheDir
            else -> null
        }
        return dir ?: throw FileNotFoundException("Unknown or inaccessible root: $rootId")
    }

    private fun buildDocumentId(rootId: String, rootDir: File, file: File): String {
        val rootCanonical = rootDir.canonicalPath
        val fileCanonical = file.canonicalPath
        if (fileCanonical == rootCanonical) {
            return "$rootId:"
        }
        val prefix = if (rootCanonical.endsWith(File.separator)) {
            rootCanonical
        } else {
            "$rootCanonical${File.separator}"
        }
        if (!fileCanonical.startsWith(prefix)) {
            throw FileNotFoundException("File is outside root: $fileCanonical")
        }
        val rel = fileCanonical.substring(prefix.length).replace(File.separatorChar, '/')
        return "$rootId:$rel"
    }

    private fun parseDocumentId(documentId: String): Pair<String, String> {
        val idx = documentId.indexOf(':')
        if (idx <= 0) {
            throw FileNotFoundException("Invalid document ID: $documentId")
        }
        val rootId = documentId.substring(0, idx)
        val relPath = documentId.substring(idx + 1).trimStart('/')
        return rootId to relPath
    }

    private fun resolveFile(documentId: String): Triple<String, File, File> {
        val (rootId, relPath) = parseDocumentId(documentId)
        val rootDir = resolveRootDir(rootId)
        val rootCanonical = rootDir.canonicalFile
        val target = if (relPath.isEmpty()) rootCanonical else File(rootCanonical, relPath)
        val targetCanonical = target.canonicalFile
        val rootPrefix = if (rootCanonical.path.endsWith(File.separator)) {
            rootCanonical.path
        } else {
            "${rootCanonical.path}${File.separator}"
        }
        if (targetCanonical.path != rootCanonical.path &&
            !targetCanonical.path.startsWith(rootPrefix)
        ) {
            throw FileNotFoundException("Path traversal rejected: $documentId")
        }
        return Triple(rootId, rootCanonical, targetCanonical)
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cols = projection ?: DEFAULT_ROOT_PROJECTION
        val result = MatrixCursor(cols)
        val appName = context?.getString(R.string.app_name) ?: "FP File Manager"

        val internalDir = getInternalStorageRootDir()
        if (internalDir != null) {
            addRootRow(
                cursor = result,
                rootId = ROOT_ID_INTERNAL,
                title = appName,
                summary = context?.getString(R.string.internal_storage) ?: "Internal Storage",
                dir = internalDir,
            )
        } else {
            getAppFilesRootDir()?.let { dir ->
                addRootRow(
                    cursor = result,
                    rootId = ROOT_ID_APP_FILES,
                    title = appName,
                    summary = context?.getString(R.string.app_files) ?: "App Files",
                    dir = dir,
                )
            }
        }

        val ctx = context
        if (ctx != null && SafBridge.available()) {
            try {
                val bookmarks = SafBridge.bookmarks(ctx)
                if (bookmarks.isNotEmpty()) {
                    val row = result.newRow()
                    put(result, row, Root.COLUMN_ROOT_ID, ROOT_ID_BOOKMARKS)
                    put(result, row, Root.COLUMN_DOCUMENT_ID, "$ROOT_ID_BOOKMARKS:")
                    put(result, row, Root.COLUMN_TITLE, context?.getString(R.string.bookmarks) ?: "Bookmarks")
                    put(result, row, Root.COLUMN_SUMMARY, context?.getString(R.string.bookmarked_folders) ?: "Favorite Folders")
                    put(result, row, Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_IS_CHILD)
                    put(result, row, Root.COLUMN_MIME_TYPES, "*/*")
                    put(result, row, Root.COLUMN_ICON, R.mipmap.ic_launcher)
                }
            } catch (_: Exception) {
            }

            try {
                for (remote in SafBridge.remotes(ctx)) {
                    val rootId = ROOT_PREFIX_REMOTE + remote.id
                    val row = result.newRow()
                    put(result, row, Root.COLUMN_ROOT_ID, rootId)
                    put(result, row, Root.COLUMN_DOCUMENT_ID, "$rootId:")
                    put(result, row, Root.COLUMN_TITLE, remote.name)
                    put(result, row, Root.COLUMN_SUMMARY, remote.kind.uppercase(Locale.ROOT))
                    put(result, row, Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_IS_CHILD)
                    put(result, row, Root.COLUMN_MIME_TYPES, "*/*")
                    put(result, row, Root.COLUMN_ICON, R.mipmap.ic_launcher)
                }
            } catch (_: Exception) {
                // A broken remote config must not hide the local root.
            }
        }

        return result
    }

    // Callers may request a projection subset; adding an absent column throws.
    private fun put(
        cursor: MatrixCursor,
        row: MatrixCursor.RowBuilder,
        column: String,
        value: Any?,
    ) {
        if (cursor.getColumnIndex(column) >= 0) {
            row.add(column, value)
        }
    }

    private fun addRootRow(
        cursor: MatrixCursor,
        rootId: String,
        title: String,
        summary: String,
        dir: File,
    ) {
        var flags = Root.FLAG_LOCAL_ONLY or
            Root.FLAG_SUPPORTS_IS_CHILD or
            Root.FLAG_SUPPORTS_SEARCH
        if (dir.canWrite()) {
            flags = flags or Root.FLAG_SUPPORTS_CREATE
        }
        val row = cursor.newRow()
        put(cursor, row, Root.COLUMN_ROOT_ID, rootId)
        put(cursor, row, Root.COLUMN_DOCUMENT_ID, "$rootId:")
        put(cursor, row, Root.COLUMN_TITLE, title)
        put(cursor, row, Root.COLUMN_SUMMARY, summary)
        put(cursor, row, Root.COLUMN_FLAGS, flags)
        put(cursor, row, Root.COLUMN_MIME_TYPES, "*/*")
        put(cursor, row, Root.COLUMN_ICON, R.mipmap.ic_launcher)
        put(cursor, row, Root.COLUMN_AVAILABLE_BYTES, dir.usableSpace)
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        if (documentId == "$ROOT_ID_BOOKMARKS:") {
            val row = result.newRow()
            put(result, row, Document.COLUMN_DOCUMENT_ID, "$ROOT_ID_BOOKMARKS:")
            put(result, row, Document.COLUMN_DISPLAY_NAME, context?.getString(R.string.bookmarks) ?: "Bookmarks")
            put(result, row, Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
            put(result, row, Document.COLUMN_FLAGS, 0)
            return result
        }
        val (rootId, relPath) = parseDocumentId(documentId)
        remoteIdOf(rootId)?.let { remoteId ->
            checkRemoteRel(relPath)
            val entry = if (relPath.isEmpty()) {
                org.json.JSONObject().put("is_dir", true)
            } else {
                SafBridge.stat(ctx(), remoteId, relPath)
            }
            includeRemoteEntry(result, rootId, relPath, entry)
            return result
        }
        val (_, rootDir, file) = resolveFile(documentId)
        if (!file.exists()) {
            throw FileNotFoundException("Document not found: $documentId")
        }
        includeFile(result, rootId, rootDir, file)
        return result
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        if (parentDocumentId == "$ROOT_ID_BOOKMARKS:") {
            val ctx = ctx()
            val bookmarks = SafBridge.bookmarks(ctx)
            for (b in bookmarks) {
                if (b.root.startsWith("remote://")) {
                    val remoteId = b.root.removePrefix("remote://").trimEnd('/')
                    val rel = b.path.trimStart('/')
                    val entry = try {
                        if (rel.isEmpty()) {
                            org.json.JSONObject().put("is_dir", true)
                        } else {
                            SafBridge.stat(ctx, remoteId, rel)
                        }
                    } catch (_: Exception) {
                        null
                    }
                    if (entry != null) {
                        includeRemoteEntry(result, ROOT_PREFIX_REMOTE + remoteId, rel, entry, customDisplayName = b.name)
                    }
                } else {
                    val file = if (b.path.isEmpty()) File(b.root) else File(b.root, b.path)
                    if (file.exists()) {
                        val intRoot = getInternalStorageRootDir()
                        val appRoot = getAppFilesRootDir()
                        val rootPair = when {
                            intRoot != null && file.canonicalPath.startsWith(intRoot.canonicalPath) -> (ROOT_ID_INTERNAL to intRoot)
                            appRoot != null && file.canonicalPath.startsWith(appRoot.canonicalPath) -> (ROOT_ID_APP_FILES to appRoot)
                            else -> null
                        }
                        if (rootPair != null) {
                            includeFile(result, rootPair.first, rootPair.second, file, customDisplayName = b.name)
                        }
                    }
                }
            }
            return result
        }
        val (rootId, relPath) = parseDocumentId(parentDocumentId)
        remoteIdOf(rootId)?.let { remoteId ->
            checkRemoteRel(relPath)
            val entries = SafBridge.list(ctx(), remoteId, relPath)
            for (i in 0 until entries.length()) {
                val entry = entries.optJSONObject(i) ?: continue
                val childRel = entry.optString("path").trimStart('/')
                includeRemoteEntry(result, rootId, childRel, entry)
            }
            return result
        }
        val (_, rootDir, parent) = resolveFile(parentDocumentId)
        if (!parent.exists() || !parent.isDirectory) {
            throw FileNotFoundException("Directory not found: $parentDocumentId")
        }
        val children = parent.listFiles() ?: emptyArray()
        children.sortWith(compareBy<File>({ !it.isDirectory }, { it.name.lowercase(Locale.ROOT) }))
        for (child in children) {
            includeFile(result, rootId, rootDir, child)
        }
        return result
    }

    override fun querySearchDocuments(
        rootId: String,
        query: String,
        projection: Array<out String>?,
    ): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        if (rootId == ROOT_ID_BOOKMARKS || remoteIdOf(rootId) != null) {
            return result
        }
        val rootDir = resolveRootDir(rootId).canonicalFile
        val needle = query.trim().lowercase(Locale.ROOT)
        if (needle.isEmpty()) {
            return result
        }

        val queue = ArrayDeque<File>()
        queue.add(rootDir)
        var matched = 0
        var visited = 0

        while (queue.isNotEmpty() && matched < MAX_SEARCH_RESULTS && visited < MAX_SEARCH_VISITED) {
            val current = queue.removeFirst()
            val children = current.listFiles() ?: continue
            for (child in children) {
                visited++
                if (visited >= MAX_SEARCH_VISITED) break
                if (child.name.lowercase(Locale.ROOT).contains(needle)) {
                    includeFile(result, rootId, rootDir, child)
                    matched++
                    if (matched >= MAX_SEARCH_RESULTS) break
                }
                if (child.isDirectory && !child.name.startsWith(".")) {
                    queue.addLast(child)
                }
            }
        }
        return result
    }

    override fun getDocumentType(documentId: String): String {
        if (documentId == "$ROOT_ID_BOOKMARKS:") {
            return Document.MIME_TYPE_DIR
        }
        val (rootId, relPath) = parseDocumentId(documentId)
        remoteIdOf(rootId)?.let { remoteId ->
            checkRemoteRel(relPath)
            if (relPath.isEmpty()) return Document.MIME_TYPE_DIR
            val entry = SafBridge.stat(ctx(), remoteId, relPath)
            return if (entry.optBoolean("is_dir")) {
                Document.MIME_TYPE_DIR
            } else {
                mimeForName(relPath.substringAfterLast('/'))
            }
        }
        val (_, _, file) = resolveFile(documentId)
        if (!file.exists()) {
            throw FileNotFoundException("Document not found: $documentId")
        }
        return getMimeType(file)
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        if (parentDocumentId == "$ROOT_ID_BOOKMARKS:") {
            val ctx = context ?: return false
            return try {
                for (b in SafBridge.bookmarks(ctx)) {
                    val bDocId = if (b.root.startsWith("remote://")) {
                        val rid = b.root.removePrefix("remote://").trimEnd('/')
                        ROOT_PREFIX_REMOTE + rid + ":" + b.path.trimStart('/')
                    } else {
                        val file = if (b.path.isEmpty()) File(b.root) else File(b.root, b.path)
                        val intRoot = getInternalStorageRootDir()
                        val appRoot = getAppFilesRootDir()
                        when {
                            intRoot != null && file.canonicalPath.startsWith(intRoot.canonicalPath) ->
                                buildDocumentId(ROOT_ID_INTERNAL, intRoot, file)
                            appRoot != null && file.canonicalPath.startsWith(appRoot.canonicalPath) ->
                                buildDocumentId(ROOT_ID_APP_FILES, appRoot, file)
                            else -> null
                        }
                    }
                    if (bDocId != null && (bDocId == documentId || isChildDocument(bDocId, documentId))) {
                        return true
                    }
                }
                false
            } catch (_: Exception) {
                false
            }
        }
        val (parentRoot, parentRel) = parseDocumentId(parentDocumentId)
        val (childRoot, childRel) = parseDocumentId(documentId)
        if (parentRoot != childRoot) return false
        if (remoteIdOf(parentRoot) != null) {
            checkRemoteRel(parentRel)
            checkRemoteRel(childRel)
            val prefix = if (parentRel.isEmpty()) "" else "$parentRel/"
            return childRel == parentRel || childRel.startsWith(prefix)
        }
        return try {
            val (_, _, parentFile) = resolveFile(parentDocumentId)
            val (_, _, childFile) = resolveFile(documentId)
            val parentPath = parentFile.canonicalPath
            val childPath = childFile.canonicalPath
            val prefix = if (parentPath.endsWith(File.separator)) {
                parentPath
            } else {
                "$parentPath${File.separator}"
            }
            childPath == parentPath || childPath.startsWith(prefix)
        } catch (_: Exception) {
            false
        }
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        val (rootId, relPath) = parseDocumentId(documentId)
        remoteIdOf(rootId)?.let { remoteId ->
            checkRemoteRel(relPath)
            val parentRel = relPath.substringBeforeLast('/', "")
            val cacheDir = File(ctx().cacheDir, "saf_remote/$remoteId/${hexOf(parentRel)}")
            val nativePath = SafBridge.export(ctx(), remoteId, relPath, cacheDir.absolutePath)
            val file = File(nativePath)
            if (!file.exists() || !file.isFile) {
                throw FileNotFoundException("Cannot open document: $documentId")
            }
            val accessMode = try {
                ParcelFileDescriptor.parseMode(mode)
            } catch (_: Exception) {
                ParcelFileDescriptor.MODE_READ_ONLY
            }
            return ParcelFileDescriptor.open(file, accessMode)
        }
        val (_, _, file) = resolveFile(documentId)
        if (!file.exists() || file.isDirectory) {
            throw FileNotFoundException("Cannot open document: $documentId")
        }
        val accessMode = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, accessMode)
    }

    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String,
    ): String {
        rejectRemoteMutation(parentDocumentId)
        val (rootId, rootDir, parent) = resolveFile(parentDocumentId)
        if (!parent.exists() || !parent.isDirectory) {
            throw FileNotFoundException("Parent directory not found: $parentDocumentId")
        }
        val safeName = File(displayName).name
        if (safeName.isEmpty() || safeName == "." || safeName == "..") {
            throw FileNotFoundException("Invalid display name: $displayName")
        }
        val target = resolveUniqueChild(parent, safeName, mimeType == Document.MIME_TYPE_DIR)
        val created = if (mimeType == Document.MIME_TYPE_DIR) {
            target.mkdir()
        } else {
            try {
                target.createNewFile()
            } catch (e: IOException) {
                throw FileNotFoundException("Failed to create file: ${e.message}")
            }
        }
        if (!created) {
            throw FileNotFoundException("Failed to create document: ${target.name}")
        }
        return buildDocumentId(rootId, rootDir, target)
    }

    override fun renameDocument(documentId: String, displayName: String): String {
        rejectRemoteMutation(documentId)
        val (rootId, rootDir, file) = resolveFile(documentId)
        if (!file.exists() || file.canonicalPath == rootDir.canonicalPath) {
            throw FileNotFoundException("Cannot rename document: $documentId")
        }
        val parent = file.parentFile ?: throw FileNotFoundException("Missing parent directory")
        val safeName = File(displayName).name
        if (safeName.isEmpty() || safeName == "." || safeName == "..") {
            throw FileNotFoundException("Invalid new name: $displayName")
        }
        val dest = File(parent, safeName)
        if (dest.exists() || !file.renameTo(dest)) {
            throw FileNotFoundException("Failed to rename ${file.name} to $safeName")
        }
        return buildDocumentId(rootId, rootDir, dest)
    }

    override fun deleteDocument(documentId: String) {
        rejectRemoteMutation(documentId)
        val (_, rootDir, file) = resolveFile(documentId)
        if (!file.exists() || file.canonicalPath == rootDir.canonicalPath) {
            throw FileNotFoundException("Cannot delete document: $documentId")
        }
        val deleted = if (file.isDirectory) file.deleteRecursively() else file.delete()
        if (!deleted) {
            throw FileNotFoundException("Failed to delete document: $documentId")
        }
    }

    private fun resolveUniqueChild(parent: File, name: String, isDir: Boolean): File {
        var candidate = File(parent, name)
        if (!candidate.exists()) return candidate
        val base: String
        val ext: String
        val dot = if (isDir) -1 else name.lastIndexOf('.')
        if (dot > 0) {
            base = name.substring(0, dot)
            ext = name.substring(dot)
        } else {
            base = name
            ext = ""
        }
        var counter = 1
        while (candidate.exists()) {
            candidate = File(parent, "$base ($counter)$ext")
            counter++
        }
        return candidate
    }

    private fun includeFile(
        cursor: MatrixCursor,
        rootId: String,
        rootDir: File,
        file: File,
        customDisplayName: String? = null,
    ) {
        val docId = buildDocumentId(rootId, rootDir, file)
        val mimeType = getMimeType(file)
        val isRoot = file.canonicalPath == rootDir.canonicalPath
        var flags = 0
        if (file.isDirectory) {
            if (file.canWrite()) {
                flags = flags or Document.FLAG_DIR_SUPPORTS_CREATE
            }
        } else if (file.canWrite()) {
            flags = flags or Document.FLAG_SUPPORTS_WRITE
        }
        if (!isRoot && file.parentFile?.canWrite() == true) {
            flags = flags or Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_RENAME
        }

        val displayName = customDisplayName ?: if (isRoot) {
            if (rootId == ROOT_ID_INTERNAL) {
                context?.getString(R.string.internal_storage) ?: "Internal Storage"
            } else {
                context?.getString(R.string.app_files) ?: "App Files"
            }
        } else {
            file.name
        }

        val row = cursor.newRow()
        put(cursor, row, Document.COLUMN_DOCUMENT_ID, docId)
        put(cursor, row, Document.COLUMN_DISPLAY_NAME, displayName)
        put(cursor, row, Document.COLUMN_SIZE, if (file.isDirectory) 0L else file.length())
        put(cursor, row, Document.COLUMN_MIME_TYPE, mimeType)
        put(cursor, row, Document.COLUMN_LAST_MODIFIED, file.lastModified())
        put(cursor, row, Document.COLUMN_FLAGS, flags)
    }

    private fun ctx(): android.content.Context =
        context ?: throw FileNotFoundException("provider context unavailable")

    private fun remoteIdOf(rootId: String): String? =
        if (rootId.startsWith(ROOT_PREFIX_REMOTE)) {
            rootId.substring(ROOT_PREFIX_REMOTE.length)
        } else {
            null
        }

    // docIds arrive from untrusted intents; ".." must not climb out of the
    // configured remote root on the server side.
    private fun checkRemoteRel(rel: String) {
        if (rel.split('/').any { it == ".." }) {
            throw FileNotFoundException("Path traversal rejected: $rel")
        }
    }

    private fun rejectRemoteMutation(documentId: String) {
        val (rootId, _) = parseDocumentId(documentId)
        if (rootId == ROOT_ID_BOOKMARKS || remoteIdOf(rootId) != null) {
            throw FileNotFoundException("Read-only document: $documentId")
        }
    }

    private fun includeRemoteEntry(
        cursor: MatrixCursor,
        rootId: String,
        rel: String,
        entry: org.json.JSONObject,
        customDisplayName: String? = null,
    ) {
        val isDir = entry.optBoolean("is_dir", false)
        val displayName = customDisplayName ?: if (rel.isEmpty()) {
            remoteRootTitle(rootId)
        } else {
            rel.substringAfterLast('/')
        }
        val row = cursor.newRow()
        put(cursor, row, Document.COLUMN_DOCUMENT_ID, "$rootId:$rel")
        put(cursor, row, Document.COLUMN_DISPLAY_NAME, displayName)
        put(cursor, row, Document.COLUMN_SIZE, if (isDir) 0L else entry.optLong("size", 0L))
        put(cursor, row, Document.COLUMN_MIME_TYPE, if (isDir) Document.MIME_TYPE_DIR else mimeForName(displayName))
        put(cursor, row, Document.COLUMN_LAST_MODIFIED, entry.optLong("modified_millis", 0L))
        put(cursor, row, Document.COLUMN_FLAGS, 0)
    }

    private fun remoteRootTitle(rootId: String): String {
        val remoteId = remoteIdOf(rootId) ?: return rootId
        return try {
            SafBridge.remotes(ctx()).firstOrNull { it.id == remoteId }?.name ?: rootId
        } catch (_: Exception) {
            rootId
        }
    }

    private fun mimeForName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        if (ext.isNotEmpty()) {
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            if (!mime.isNullOrBlank()) {
                return mime
            }
        }
        return "application/octet-stream"
    }

    private fun hexOf(value: String): String =
        value.toByteArray().joinToString("") { "%02x".format(it) }

    private fun getMimeType(file: File): String {
        if (file.isDirectory) {
            return Document.MIME_TYPE_DIR
        }
        val ext = file.extension.lowercase(Locale.ROOT)
        if (ext.isNotEmpty()) {
            val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            if (!mime.isNullOrBlank()) {
                return mime
            }
        }
        return "application/octet-stream"
    }
}
