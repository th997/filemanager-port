package com.github.th997.filemanager

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

/**
 * Synchronous bridge into the Rust VFS for the SAF DocumentsProvider, which
 * runs without a Flutter engine. Mirrors SafBridge.nativeCall in saf_jni.rs.
 */
object SafBridge {
    data class RemoteRoot(val id: String, val name: String, val kind: String)
    data class BookmarkItem(val id: String, val name: String, val root: String, val path: String)

    private var loaded = false
    private var loadFailed = false

    @JvmStatic
    private external fun nativeCall(dbPath: String, requestJson: String): String

    fun available(): Boolean {
        ensureLoaded()
        return loaded
    }

    private fun ensureLoaded() {
        if (loaded || loadFailed) return
        try {
            System.loadLibrary("fm_ffi")
            loaded = true
        } catch (_: UnsatisfiedLinkError) {
            loadFailed = true
        }
    }

    private fun call(context: Context, request: JSONObject): Any? {
        ensureLoaded()
        if (!loaded) throw FileNotFoundException("native bridge unavailable")
        val dbPath = File(context.filesDir, "filemanager.db").absolutePath
        val response = JSONObject(nativeCall(dbPath, request.toString()))
        if (!response.optBoolean("ok", false)) {
            throw FileNotFoundException(response.optString("error", "remote request failed"))
        }
        return response.opt("data")
    }

    fun remotes(context: Context): List<RemoteRoot> {
        val req = JSONObject().put("method", "remotes")
        val data = call(context, req) as? JSONArray ?: return emptyList()
        val roots = mutableListOf<RemoteRoot>()
        for (i in 0 until data.length()) {
            val o = data.optJSONObject(i) ?: continue
            val id = o.optString("id")
            if (id.isEmpty()) continue
            roots.add(RemoteRoot(id, o.optString("name", id), o.optString("kind", "remote")))
        }
        return roots
    }

    fun bookmarks(context: Context): List<BookmarkItem> {
        val req = JSONObject().put("method", "bookmarks")
        val data = call(context, req) as? JSONArray ?: return emptyList()
        val items = mutableListOf<BookmarkItem>()
        for (i in 0 until data.length()) {
            val o = data.optJSONObject(i) ?: continue
            val root = o.optString("root")
            if (root.isEmpty()) continue
            items.add(
                BookmarkItem(
                    id = o.optString("id"),
                    name = o.optString("name", "Bookmark"),
                    root = root,
                    path = o.optString("path", ""),
                )
            )
        }
        return items
    }

    private fun rootOf(remoteId: String) = "remote://$remoteId"

    fun list(context: Context, remoteId: String, rel: String): JSONArray {
        val req = JSONObject()
            .put("method", "list")
            .put("root", rootOf(remoteId))
            .put("path", rel)
        return call(context, req) as? JSONArray ?: JSONArray()
    }

    fun stat(context: Context, remoteId: String, rel: String): JSONObject {
        val req = JSONObject()
            .put("method", "stat")
            .put("root", rootOf(remoteId))
            .put("path", rel)
        return call(context, req) as? JSONObject
            ?: throw FileNotFoundException("stat returned no entry: $rel")
    }

    fun export(context: Context, remoteId: String, rel: String, cacheDir: String): String {
        val req = JSONObject()
            .put("method", "export")
            .put("root", rootOf(remoteId))
            .put("path", rel)
            .put("cache_dir", cacheDir)
        return call(context, req) as? String
            ?: throw FileNotFoundException("export returned no path: $rel")
    }
}