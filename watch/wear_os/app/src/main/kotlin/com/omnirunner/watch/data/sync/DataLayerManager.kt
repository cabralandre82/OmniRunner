package com.omnirunner.watch.data.sync

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.NodeClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

/**
 * Manages the Wearable DataLayer API on the **watch side**.
 *
 * Responsibilities:
 * - Send full workout session via [DataClient.putDataItem] on workout end
 * - Send periodic live samples via [MessageClient.sendMessage] during workout
 * - Send workout state updates via [DataClient.putDataItem]
 * - Track transfer state and phone reachability
 *
 * Equivalent of Apple Watch's `WatchConnectivityManager.swift`.
 *
 * Architecture reference: docs/WatchArchitecture.md §3.2
 */
class DataLayerManager(private val context: Context) {

    /** Persistent on-disk queue for sessions that haven't been ACK'd. */
    val offlineStore = OfflineSessionStore(context)

    companion object {
        private const val TAG = "DataLayerManager"

        // DataItem paths
        const val PATH_SESSION = "/omnirunner/session"
        const val PATH_STATE = "/omnirunner/state"

        // Message paths
        const val PATH_LIVE_SAMPLE = "/omnirunner/live_sample"

        // Incoming message paths (from phone)
        const val PATH_ACK = "/omnirunner/ack"
        const val PATH_SETTINGS = "/omnirunner/settings"

        /** Interval between live sample messages (ms). */
        private const val LIVE_INTERVAL_MS = 5_000L
    }

    // ── Public State ────────────────────────────────────────────────

    enum class TransferState { IDLE, TRANSFERRING, SYNCED, FAILED }

    private val _transferState = MutableStateFlow(TransferState.IDLE)
    val transferState: StateFlow<TransferState> = _transferState.asStateFlow()

    private val _isPhoneReachable = MutableStateFlow(false)
    val isPhoneReachable: StateFlow<Boolean> = _isPhoneReachable.asStateFlow()

    private val _lastSyncedSessionId = MutableStateFlow<String?>(null)
    val lastSyncedSessionId: StateFlow<String?> = _lastSyncedSessionId.asStateFlow()

    // ── Clients ─────────────────────────────────────────────────────

    private val dataClient: DataClient by lazy { Wearable.getDataClient(context) }
    private val messageClient: MessageClient by lazy { Wearable.getMessageClient(context) }
    private val nodeClient: NodeClient by lazy { Wearable.getNodeClient(context) }

    // ── Internal ────────────────────────────────────────────────────

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var lastLiveSendMs: Long = 0L
    private var phoneNodeId: String? = null

    // ── Retry State ──────────────────────────────────────────────────

    /** Stores the last session JSON that failed to transfer for retry. */
    private var pendingSessionJSON: Map<String, Any>? = null

    /** Number of consecutive retry attempts. */
    private var retryCount: Int = 0

    /** Maximum retries before giving up. */
    private val maxRetries: Int = 5

    // ═══════════════════════════════════════════════════════════════
    //  Send Full Session (DataItem)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Transfer a completed workout session to the phone.
     *
     * Uses [DataClient.putDataItem] which reliably syncs even when the
     * phone is not immediately reachable — Google Play Services queues
     * and delivers when possible.
     *
     * The session JSON is stored as a single string in the DataMap
     * to avoid DataItem size limits with complex nested structures.
     */
    fun transferSession(sessionJSON: Map<String, Any>) {
        // Always persist to disk first — survives process termination
        offlineStore.save(sessionJSON)
        pendingSessionJSON = sessionJSON

        scope.launch {
            try {
                _transferState.value = TransferState.TRANSFERRING

                val jsonString = JSONObject(sessionJSON).toString()
                val sessionId = sessionJSON["sessionId"] as? String ?: "unknown"

                val putDataMapRequest = PutDataMapRequest.create(
                    "$PATH_SESSION/$sessionId",
                ).apply {
                    dataMap.putString("type", "workout_session")
                    dataMap.putString("sessionId", sessionId)
                    dataMap.putString("payload", jsonString)
                    dataMap.putLong("timestampMs", System.currentTimeMillis())
                    dataMap.putInt("version", 1)
                }

                putDataMapRequest.setUrgent()
                val request = putDataMapRequest.asPutDataRequest()

                dataClient.putDataItem(request).await()

                Log.d(
                    TAG,
                    "Session transferred: $sessionId (${jsonString.length} chars)",
                )
            } catch (e: Exception) {
                Log.e(TAG, "Session transfer failed", e)
                _transferState.value = TransferState.FAILED
                scheduleRetry()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Send Live Sample (Message)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Send a periodic live update to the phone if it's reachable.
     *
     * Uses [MessageClient.sendMessage] — fire-and-forget, only works
     * if the phone node is connected. Throttled to [LIVE_INTERVAL_MS]
     * (5s) to conserve battery.
     */
    fun sendLiveSampleIfNeeded(
        sessionId: String,
        bpm: Int,
        paceSecondsPerKm: Double,
        distanceM: Double,
        elapsedS: Int,
    ) {
        val now = System.currentTimeMillis()
        if (now - lastLiveSendMs < LIVE_INTERVAL_MS) return
        lastLiveSendMs = now

        scope.launch {
            val nodeId = getPhoneNodeId() ?: return@launch

            try {
                val json = JSONObject().apply {
                    put("type", "live_sample")
                    put("sessionId", sessionId)
                    put("bpm", bpm)
                    put("pace", paceSecondsPerKm)
                    put("distanceM", distanceM)
                    put("elapsedS", elapsedS)
                    put("timestampMs", now)
                }

                messageClient.sendMessage(
                    nodeId,
                    PATH_LIVE_SAMPLE,
                    json.toString().toByteArray(Charsets.UTF_8),
                ).await()
            } catch (e: Exception) {
                // Fire-and-forget: log but don't fail the workout
                Log.d(TAG, "Live sample send failed (phone unreachable)")
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Send Workout State Update (DataItem)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Notify the phone about workout state changes (running, paused, ended).
     *
     * Uses [DataClient.putDataItem] which persists even if the phone
     * is temporarily disconnected.
     */
    fun sendStateUpdate(sessionId: String, state: String) {
        scope.launch {
            try {
                val putDataMapRequest = PutDataMapRequest.create(PATH_STATE).apply {
                    dataMap.putString("type", "workout_state")
                    dataMap.putString("sessionId", sessionId)
                    dataMap.putString("state", state)
                    dataMap.putLong("timestampMs", System.currentTimeMillis())
                }

                putDataMapRequest.setUrgent()
                val request = putDataMapRequest.asPutDataRequest()

                dataClient.putDataItem(request).await()

                Log.d(TAG, "State update sent: $state (session=$sessionId)")
            } catch (e: Exception) {
                Log.e(TAG, "State update failed", e)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Handle ACK from Phone
    // ═══════════════════════════════════════════════════════════════

    /**
     * Called by [WearListenerService] when the phone acknowledges a session.
     */
    fun onAckReceived(sessionId: String) {
        _lastSyncedSessionId.value = sessionId
        _transferState.value = TransferState.SYNCED
        pendingSessionJSON = null
        retryCount = 0
        offlineStore.remove(sessionId)
        Log.d(TAG, "ACK received for session: $sessionId")

        // Sync next pending offline session (if any)
        syncNextOfflineSession()
    }

    // ═══════════════════════════════════════════════════════════════
    //  Reconnection & Retry
    // ═══════════════════════════════════════════════════════════════

    /**
     * Called when the phone node reconnects (peer connected event).
     *
     * Invalidates the cached node ID (it may have changed) and
     * retries any pending transfer.
     */
    fun onPhoneReconnected(nodeId: String) {
        phoneNodeId = nodeId
        _isPhoneReachable.value = true
        Log.d(TAG, "Phone reconnected: $nodeId — checking pending transfers")

        if (pendingSessionJSON != null) {
            retryPendingTransferIfNeeded()
        } else {
            syncAllOfflineSessions()
        }
    }

    /**
     * Called when the phone node disconnects.
     *
     * Clears the cached node ID so it's re-resolved on next attempt.
     */
    fun onPhoneDisconnected() {
        phoneNodeId = null
        _isPhoneReachable.value = false
        Log.d(TAG, "Phone disconnected — node cache cleared")
    }

    /**
     * Retry the pending session transfer if one exists.
     *
     * Respects [maxRetries] to avoid infinite loops.
     */
    fun retryPendingTransferIfNeeded() {
        val pending = pendingSessionJSON ?: return

        if (_transferState.value == TransferState.SYNCED) {
            pendingSessionJSON = null
            retryCount = 0
            return
        }

        if (retryCount >= maxRetries) {
            Log.w(TAG, "Max retries ($maxRetries) reached — giving up")
            return
        }

        retryCount++
        Log.d(TAG, "Retrying transfer (attempt $retryCount/$maxRetries)")
        transferSession(pending)
    }

    /**
     * Schedule a retry with exponential backoff.
     */
    private fun scheduleRetry() {
        if (retryCount >= maxRetries) return

        val delayMs = minOf(1000L * (1L shl retryCount), 30_000L)
        scope.launch {
            kotlinx.coroutines.delay(delayMs)
            retryPendingTransferIfNeeded()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Offline Sync
    // ═══════════════════════════════════════════════════════════════

    /**
     * Sync all pending offline sessions to the phone.
     *
     * Called on app launch and when the phone reconnects.
     * Sends the oldest un-synced session first (FIFO). Subsequent
     * sessions are sent via [syncNextOfflineSession] after each ACK.
     */
    fun syncAllOfflineSessions() {
        val sessions = offlineStore.loadAll()
        val first = sessions.firstOrNull() ?: return

        Log.d(TAG, "Syncing ${sessions.size} offline session(s)")
        pendingSessionJSON = first
        retryCount = 0
        transferSession(first)
    }

    /**
     * Send the next pending offline session (if any).
     *
     * Called after an ACK removes the just-synced session from the store.
     */
    private fun syncNextOfflineSession() {
        val sessions = offlineStore.loadAll()
        val next = sessions.firstOrNull() ?: run {
            Log.d(TAG, "No more offline sessions to sync")
            return
        }

        val sessionId = next["sessionId"] as? String ?: "unknown"
        Log.d(TAG, "Syncing next offline session: $sessionId")
        pendingSessionJSON = next
        retryCount = 0
        transferSession(next)
    }

    // ═══════════════════════════════════════════════════════════════
    //  Reset / Query
    // ═══════════════════════════════════════════════════════════════

    fun resetTransferState() {
        _transferState.value = TransferState.IDLE
        lastLiveSendMs = 0L
        pendingSessionJSON = null
        retryCount = 0
    }

    /**
     * Check if the phone node is currently reachable.
     */
    fun checkPhoneReachability() {
        scope.launch {
            val nodeId = getPhoneNodeId()
            _isPhoneReachable.value = nodeId != null
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Node Resolution
    // ═══════════════════════════════════════════════════════════════

    /**
     * Find the connected phone node ID.
     *
     * Caches the result — the phone node rarely changes during a session.
     * Returns null if no connected phone is found.
     */
    private suspend fun getPhoneNodeId(): String? {
        phoneNodeId?.let { return it }

        return try {
            val nodes = nodeClient.connectedNodes.await()
            val phone = nodes.firstOrNull { it.isNearby }
                ?: nodes.firstOrNull()

            phone?.id?.also {
                phoneNodeId = it
                _isPhoneReachable.value = true
                Log.d(TAG, "Phone node found: $it (${phone.displayName})")
            }
        } catch (e: Exception) {
            Log.d(TAG, "No phone node found")
            _isPhoneReachable.value = false
            null
        }
    }
}
