package com.omnirunner.omni_runner

import android.util.Log
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/**
 * Listens for data and messages from the WearOS watch via DataLayer API.
 *
 * Receives:
 * - Full workout sessions via [DataEvent] (DataItem at /omnirunner/session/{id})
 * - Workout state updates via [DataEvent] (DataItem at /omnirunner/state)
 * - Live samples via [MessageEvent] (message at /omnirunner/live_sample)
 *
 * Forwards all events to [PhoneDataLayerManager] which bridges to Flutter
 * via MethodChannel.
 *
 * Equivalent of iOS `PhoneConnectivityManager.session(_:didReceive:)`.
 */
class PhoneWearListenerService : WearableListenerService() {

    companion object {
        private const val TAG = "PhoneWearListener"

        const val PATH_SESSION_PREFIX = "/omnirunner/session/"
        const val PATH_STATE = "/omnirunner/state"
        const val PATH_LIVE_SAMPLE = "/omnirunner/live_sample"
    }

    // ── DataItem events (session + state) ───────────────────────────

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        Log.d(TAG, "Data changed: ${dataEvents.count} events")

        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue

            val path = event.dataItem.uri.path ?: continue
            val dataMapItem = DataMapItem.fromDataItem(event.dataItem)
            val dataMap = dataMapItem.dataMap

            when {
                path.startsWith(PATH_SESSION_PREFIX) -> {
                    handleSessionReceived(dataMap, path)
                }
                path == PATH_STATE -> {
                    handleStateUpdate(dataMap)
                }
                else -> {
                    Log.d(TAG, "Unknown data path: $path")
                }
            }
        }
    }

    private fun handleSessionReceived(
        dataMap: com.google.android.gms.wearable.DataMap,
        path: String,
    ) {
        val sessionId = dataMap.getString("sessionId", "unknown")
        val payload = dataMap.getString("payload", "")

        if (payload.isEmpty()) {
            Log.w(TAG, "Empty session payload for: $sessionId")
            return
        }

        try {
            val json = JSONObject(payload)
            val sessionMap = jsonToMap(json)

            Log.d(TAG, "Session received: $sessionId (${payload.length} chars)")

            PhoneDataLayerManager.shared.onSessionReceived(sessionMap)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse session JSON", e)
        }
    }

    private fun handleStateUpdate(
        dataMap: com.google.android.gms.wearable.DataMap,
    ) {
        val stateData = mapOf(
            "type" to dataMap.getString("type", "workout_state"),
            "sessionId" to dataMap.getString("sessionId", ""),
            "state" to dataMap.getString("state", ""),
            "timestampMs" to dataMap.getLong("timestampMs", 0L),
        )

        Log.d(TAG, "Watch state: ${stateData["state"]} (session=${stateData["sessionId"]})")

        PhoneDataLayerManager.shared.onWatchStateChanged(stateData)
    }

    // ── Message events (live samples) ───────────────────────────────

    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            PATH_LIVE_SAMPLE -> {
                handleLiveSample(messageEvent)
            }
            else -> {
                Log.d(TAG, "Unknown message path: ${messageEvent.path}")
            }
        }
    }

    private fun handleLiveSample(event: MessageEvent) {
        try {
            val jsonString = String(event.data, Charsets.UTF_8)
            val json = JSONObject(jsonString)
            val sampleMap = jsonToMap(json)

            PhoneDataLayerManager.shared.onLiveSample(sampleMap)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse live sample", e)
        }
    }

    // ── Node connectivity ───────────────────────────────────────────

    override fun onPeerConnected(node: com.google.android.gms.wearable.Node) {
        Log.d(TAG, "Watch connected: ${node.displayName} (${node.id})")
        PhoneDataLayerManager.shared.onReachabilityChanged(true)
    }

    override fun onPeerDisconnected(node: com.google.android.gms.wearable.Node) {
        Log.d(TAG, "Watch disconnected: ${node.displayName} (${node.id})")
        PhoneDataLayerManager.shared.onReachabilityChanged(false)
    }

    // ── JSON helpers ────────────────────────────────────────────────

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
