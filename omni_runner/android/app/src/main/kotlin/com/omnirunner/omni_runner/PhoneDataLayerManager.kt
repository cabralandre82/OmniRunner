package com.omnirunner.omni_runner

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.NodeClient
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Manages the Wearable DataLayer API on the **phone (Android) side**.
 *
 * Responsibilities:
 * - Provide Flutter MethodChannel ("omnirunner/watch") for Dart ↔ native
 * - Forward received workout sessions and live samples to Flutter
 * - Send ACK messages back to the watch
 * - Query watch connectivity status
 *
 * Equivalent of iOS `PhoneConnectivityManager.swift`.
 *
 * Architecture reference: docs/WatchArchitecture.md §6
 */
class PhoneDataLayerManager private constructor() {

    companion object {
        private const val TAG = "PhoneDataLayer"
        const val CHANNEL_NAME = "omnirunner/watch"

        const val PATH_ACK = "/omnirunner/ack"

        /** Singleton instance. */
        val shared = PhoneDataLayerManager()
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val messageClient: MessageClient?
        get() = context?.let { Wearable.getMessageClient(it) }

    private val nodeClient: NodeClient?
        get() = context?.let { Wearable.getNodeClient(it) }

    // ═══════════════════════════════════════════════════════════════
    //  Setup
    // ═══════════════════════════════════════════════════════════════

    /**
     * Configure the MethodChannel and store context.
     *
     * Call from `MainActivity.configureFlutterEngine()`.
     */
    fun setup(context: Context, binaryMessenger: BinaryMessenger) {
        this.context = context.applicationContext

        channel = MethodChannel(binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(::handleFlutterCall)
        }

        Log.d(TAG, "PhoneDataLayerManager initialized")
    }

    // ═══════════════════════════════════════════════════════════════
    //  Flutter → Native Method Calls
    // ═══════════════════════════════════════════════════════════════

    private fun handleFlutterCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acknowledgeSession" -> {
                val sessionId = call.argument<String>("sessionId")
                if (sessionId == null) {
                    result.error("INVALID_ARGS", "sessionId required", null)
                    return
                }
                acknowledgeSession(sessionId)
                result.success(null)
            }
            "getWatchStatus" -> {
                getWatchStatus(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  ACK to Watch
    // ═══════════════════════════════════════════════════════════════

    /**
     * Tell the watch we've received and processed a session.
     *
     * Uses [MessageClient.sendMessage] to send the session ID back.
     */
    private fun acknowledgeSession(sessionId: String) {
        scope.launch {
            try {
                val nodeId = getWatchNodeId() ?: run {
                    Log.w(TAG, "Cannot ACK: no watch node found")
                    return@launch
                }

                messageClient?.sendMessage(
                    nodeId,
                    PATH_ACK,
                    sessionId.toByteArray(Charsets.UTF_8),
                )?.await()

                Log.d(TAG, "ACK sent to watch: $sessionId")
            } catch (e: Exception) {
                Log.e(TAG, "ACK send failed", e)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Watch Status
    // ═══════════════════════════════════════════════════════════════

    private fun getWatchStatus(result: MethodChannel.Result) {
        scope.launch {
            try {
                val nodes = nodeClient?.connectedNodes?.await() ?: emptyList()
                val watchNode = nodes.firstOrNull()

                val status = mapOf(
                    "isSupported" to true,
                    "isReachable" to (watchNode != null),
                    "isPaired" to (watchNode != null),
                    "nodeId" to (watchNode?.id ?: ""),
                    "displayName" to (watchNode?.displayName ?: ""),
                    "connectedNodes" to nodes.size,
                )

                result.success(status)
            } catch (e: Exception) {
                Log.e(TAG, "getWatchStatus failed", e)
                result.success(
                    mapOf(
                        "isSupported" to false,
                        "isReachable" to false,
                        "isPaired" to false,
                        "error" to e.message,
                    ),
                )
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Events from Watch (called by PhoneWearListenerService)
    // ═══════════════════════════════════════════════════════════════

    /**
     * Forward a received full workout session to Flutter.
     */
    fun onSessionReceived(sessionJson: Map<String, Any>) {
        Log.d(TAG, "Forwarding session to Flutter: ${sessionJson["sessionId"]}")
        invokeFlutterMethod("onSessionReceived", sessionJson)
    }

    /**
     * Forward a live sample to Flutter.
     */
    fun onLiveSample(sampleData: Map<String, Any>) {
        invokeFlutterMethod("onLiveSample", sampleData)
    }

    /**
     * Forward a watch state change to Flutter.
     */
    fun onWatchStateChanged(stateData: Map<String, Any>) {
        Log.d(TAG, "Watch state changed: ${stateData["state"]}")
        invokeFlutterMethod("onWatchStateChanged", stateData)
    }

    /**
     * Notify Flutter about watch reachability changes.
     */
    fun onReachabilityChanged(isReachable: Boolean) {
        invokeFlutterMethod(
            "onReachabilityChanged",
            mapOf("isReachable" to isReachable),
        )
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private Helpers
    // ═══════════════════════════════════════════════════════════════

    private fun invokeFlutterMethod(method: String, arguments: Any?) {
        val ch = channel ?: return
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            ch.invokeMethod(method, arguments)
        }
    }

    private suspend fun getWatchNodeId(): String? {
        return try {
            val nodes = nodeClient?.connectedNodes?.await() ?: emptyList()
            nodes.firstOrNull()?.id
        } catch (e: Exception) {
            Log.d(TAG, "No watch node found")
            null
        }
    }
}
