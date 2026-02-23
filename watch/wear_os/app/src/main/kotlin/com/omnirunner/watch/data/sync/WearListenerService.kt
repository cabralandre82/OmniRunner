package com.omnirunner.watch.data.sync

import android.util.Log
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import com.omnirunner.watch.OmniRunnerWatchApp

/**
 * Listens for messages, data changes, and peer connectivity events
 * from the phone app via DataLayer API.
 *
 * Receives:
 * - ACK messages when the phone processes a workout session
 * - Settings updates (maxHR, alerts) from the phone
 * - Peer connected/disconnected events for reconnection handling
 *
 * Forwards events to [DataLayerManager] for state updates and retry logic.
 */
class WearListenerService : WearableListenerService() {

    companion object {
        const val TAG = "WearListenerService"
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Message received: ${messageEvent.path}")

        val dataLayerManager = getDataLayerManager()

        when (messageEvent.path) {
            DataLayerManager.PATH_ACK -> {
                val sessionId = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "ACK received for session: $sessionId")
                dataLayerManager?.onAckReceived(sessionId)
            }
            DataLayerManager.PATH_SETTINGS -> {
                val settingsJson = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Settings received from phone: $settingsJson")
            }
            else -> {
                Log.w(TAG, "Unknown message path: ${messageEvent.path}")
            }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        Log.d(TAG, "Data changed: ${dataEvents.count} events")
        for (event in dataEvents) {
            val path = event.dataItem.uri.path ?: ""
            Log.d(TAG, "  event path=$path, type=${event.type}")
        }
    }

    // ── Peer Connectivity ────────────────────────────────────────────

    override fun onPeerConnected(peer: Node) {
        Log.d(TAG, "Phone connected: ${peer.displayName} (${peer.id})")
        getDataLayerManager()?.onPhoneReconnected(peer.id)
    }

    override fun onPeerDisconnected(peer: Node) {
        Log.d(TAG, "Phone disconnected: ${peer.displayName} (${peer.id})")
        getDataLayerManager()?.onPhoneDisconnected()
    }

    private fun getDataLayerManager(): DataLayerManager? {
        return (application as? OmniRunnerWatchApp)?.dataLayerManager
    }
}
