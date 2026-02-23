package com.omnirunner.watch.data.sync

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Persistent offline queue for completed workout sessions.
 *
 * Stores sessions as individual JSON files in the app's internal
 * storage directory so they survive app/process termination.
 * Each session is identified by its `sessionId`.
 *
 * Usage:
 * 1. [save] — after workout ends, before attempting transfer
 * 2. [remove] — after receiving ACK from the phone
 * 3. [loadAll] — on app launch, to retry un-synced sessions
 *
 * Equivalent of Apple Watch's `OfflineSessionStore.swift`.
 */
class OfflineSessionStore(context: Context) {

    companion object {
        private const val TAG = "OfflineSessionStore"
        private const val DIR_NAME = "pending_sessions"
    }

    private val storeDir: File = File(context.filesDir, DIR_NAME).also {
        if (!it.exists()) it.mkdirs()
    }

    // ═══════════════════════════════════════════════════════════════
    //  Save
    // ═══════════════════════════════════════════════════════════════

    /**
     * Persist a session JSON to disk.
     *
     * Overwrites any existing file with the same sessionId (idempotent).
     */
    fun save(session: Map<String, Any>) {
        val sessionId = session["sessionId"] as? String
        if (sessionId.isNullOrEmpty()) {
            Log.w(TAG, "Cannot save session without sessionId")
            return
        }

        try {
            val jsonString = JSONObject(session).toString()
            val file = fileFor(sessionId)
            file.writeText(jsonString, Charsets.UTF_8)
            Log.d(TAG, "Saved session: $sessionId (${jsonString.length} chars)")
        } catch (e: Exception) {
            Log.e(TAG, "Save error for $sessionId", e)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Remove
    // ═══════════════════════════════════════════════════════════════

    /**
     * Delete a session from the offline store (called after ACK).
     */
    fun remove(sessionId: String) {
        val file = fileFor(sessionId)
        if (file.exists()) {
            file.delete()
            Log.d(TAG, "Removed synced session: $sessionId")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Load All
    // ═══════════════════════════════════════════════════════════════

    /**
     * Load all pending (un-synced) sessions from disk.
     *
     * Returns a list of session JSON maps, sorted by file modification
     * date (oldest first — FIFO).
     */
    fun loadAll(): List<Map<String, Any>> {
        val files = storeDir.listFiles { f -> f.extension == "json" }
            ?: return emptyList()

        val sessions = files
            .sortedBy { it.lastModified() }
            .mapNotNull { file ->
                try {
                    val jsonString = file.readText(Charsets.UTF_8)
                    val json = JSONObject(jsonString)
                    jsonToMap(json)
                } catch (e: Exception) {
                    Log.e(TAG, "Load error for ${file.name}", e)
                    null
                }
            }

        if (sessions.isNotEmpty()) {
            Log.d(TAG, "Loaded ${sessions.size} pending session(s)")
        }

        return sessions
    }

    // ═══════════════════════════════════════════════════════════════
    //  Query
    // ═══════════════════════════════════════════════════════════════

    /** Number of pending sessions on disk. */
    val pendingCount: Int
        get() = storeDir.listFiles { f -> f.extension == "json" }?.size ?: 0

    /** Check if a specific session exists in the offline store. */
    fun contains(sessionId: String): Boolean = fileFor(sessionId).exists()

    // ═══════════════════════════════════════════════════════════════
    //  Private
    // ═══════════════════════════════════════════════════════════════

    private fun fileFor(sessionId: String): File {
        val safeName = sessionId
            .replace("/", "_")
            .replace("..", "_")
        return File(storeDir, "session_$safeName.json")
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        return map
    }

    private fun jsonArrayToList(array: org.json.JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(
                when (value) {
                    is JSONObject -> jsonToMap(value)
                    is org.json.JSONArray -> jsonArrayToList(value)
                    else -> value
                },
            )
        }
        return list
    }
}
