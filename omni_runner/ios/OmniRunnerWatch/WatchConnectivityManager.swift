import Foundation
import WatchConnectivity

/// Manages WatchConnectivity on the **watch side**.
///
/// Responsibilities:
/// - Activate `WCSession`
/// - Send full workout session via `transferFile()` on workout end
/// - Send periodic live samples via `sendMessage()` during workout
/// - Receive ACK and settings from phone via `applicationContext`
///
/// Architecture reference: docs/WatchArchitecture.md §3.1
final class WatchConnectivityManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isReachable: Bool = false
    @Published var lastSyncedSessionId: String?
    @Published var transferState: TransferState = .idle

    enum TransferState: String {
        case idle
        case transferring
        case synced
        case failed
    }

    // MARK: - Offline Store

    /// Persistent on-disk queue for sessions that haven't been ACK'd.
    private let offlineStore = OfflineSessionStore.shared

    // MARK: - Pending Session (retry on reconnect)

    /// Stores the last session that failed to transfer so it can be
    /// retried when the phone becomes reachable again.
    private var pendingSessionJSON: [String: Any]?

    /// Number of consecutive retry attempts for the current pending session.
    private var retryCount: Int = 0

    /// Maximum retries before giving up on a pending session.
    private let maxRetries: Int = 5

    // MARK: - Configuration

    /// Interval between live sample messages (seconds).
    private let liveInterval: TimeInterval = 5.0
    private var lastLiveSendTime: Date?

    // MARK: - Init

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            print("[WatchConnectivity] WCSession not supported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send Full Session (File Transfer)

    /// Transfer a completed workout session to the phone.
    ///
    /// Uses `transferFile()` which works even when the phone is not
    /// immediately reachable — the system queues and delivers when possible.
    func transferSession(_ sessionJSON: [String: Any]) {
        // Always persist to disk first — survives app termination
        offlineStore.save(session: sessionJSON)

        guard WCSession.default.activationState == .activated else {
            print("[WatchConnectivity] Session not activated — saved offline")
            pendingSessionJSON = sessionJSON
            transferState = .failed
            return
        }

        do {
            let data = try JSONSerialization.data(
                withJSONObject: sessionJSON, options: []
            )

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "session_\(sessionJSON["sessionId"] ?? "unknown").json"
            let fileURL = tempDir.appendingPathComponent(fileName)

            try data.write(to: fileURL)

            let metadata: [String: Any] = [
                "type": "workout_session",
                "sessionId": sessionJSON["sessionId"] as? String ?? "",
                "version": 1,
            ]

            WCSession.default.transferFile(fileURL, metadata: metadata)
            transferState = .transferring
            pendingSessionJSON = sessionJSON

            print(
                "[WatchConnectivity] File transfer queued: \(fileName)"
                    + " (\(data.count) bytes)"
            )
        } catch {
            print("[WatchConnectivity] Transfer error: \(error)")
            pendingSessionJSON = sessionJSON
            transferState = .failed
        }
    }

    // MARK: - Retry Pending

    /// Retry transferring a pending session.
    ///
    /// Called automatically when the phone becomes reachable or when
    /// a previous file transfer fails. Respects `maxRetries` to avoid
    /// infinite loops.
    func retryPendingTransferIfNeeded() {
        guard let pending = pendingSessionJSON else { return }
        guard transferState != .synced else {
            pendingSessionJSON = nil
            return
        }
        guard retryCount < maxRetries else {
            print(
                "[WatchConnectivity] Max retries (\(maxRetries)) reached"
                    + " — giving up on pending session"
            )
            return
        }

        retryCount += 1
        print(
            "[WatchConnectivity] Retrying transfer (attempt \(retryCount)"
                + "/\(maxRetries))"
        )
        transferSession(pending)
    }

    // MARK: - Offline Sync

    /// Sync all pending offline sessions to the phone.
    ///
    /// Called on app launch and when reachability changes to `true`.
    /// Sends the oldest un-synced session first (FIFO). Subsequent
    /// sessions are sent via `syncNextOfflineSession()` after each ACK.
    func syncAllOfflineSessions() {
        let sessions = offlineStore.loadAll()
        guard let first = sessions.first else { return }

        print(
            "[WatchConnectivity] Syncing \(sessions.count) offline session(s)"
        )
        pendingSessionJSON = first
        retryCount = 0
        transferSession(first)
    }

    /// Send the next pending offline session (if any).
    ///
    /// Called after an ACK removes the just-synced session from the store.
    private func syncNextOfflineSession() {
        let sessions = offlineStore.loadAll()
        guard let next = sessions.first else {
            print("[WatchConnectivity] No more offline sessions to sync")
            return
        }

        let sessionId = next["sessionId"] as? String ?? "unknown"
        print("[WatchConnectivity] Syncing next offline session: \(sessionId)")
        pendingSessionJSON = next
        retryCount = 0
        transferSession(next)
    }

    // MARK: - Send Live Sample (Interactive Message)

    /// Send a periodic live update to the phone if it's reachable.
    ///
    /// Called from `WatchWorkoutManager` during an active workout.
    /// Throttled to `liveInterval` (5s) to conserve battery.
    /// Uses `sendMessage()` — fire-and-forget, only works if phone is
    /// reachable (both apps running or phone in foreground).
    func sendLiveSampleIfNeeded(
        sessionId: String,
        bpm: Int,
        paceSecondsPerKm: Double,
        distanceM: Double,
        elapsedS: Int
    ) {
        guard WCSession.default.isReachable else { return }

        let now = Date()
        if let last = lastLiveSendTime,
           now.timeIntervalSince(last) < liveInterval
        {
            return
        }
        lastLiveSendTime = now

        let message: [String: Any] = [
            "type": "live_sample",
            "sessionId": sessionId,
            "bpm": bpm,
            "pace": paceSecondsPerKm,
            "distanceM": distanceM,
            "elapsedS": elapsedS,
            "timestampMs": Int64(now.timeIntervalSince1970 * 1000),
        ]

        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("[WatchConnectivity] Live sample send error: \(error)")
        }
    }

    // MARK: - Send Workout State Changes

    /// Notify the phone about workout state changes (start, pause, end).
    func sendStateUpdate(sessionId: String, state: String) {
        guard WCSession.default.activationState == .activated else { return }

        let context: [String: Any] = [
            "type": "workout_state",
            "sessionId": sessionId,
            "state": state,
            "timestampMs": Int64(Date().timeIntervalSince1970 * 1000),
        ]

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("[WatchConnectivity] Context update error: \(error)")
        }
    }

    // MARK: - Reset

    func resetTransferState() {
        transferState = .idle
        lastLiveSendTime = nil
        pendingSessionJSON = nil
        retryCount = 0
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
        }

        if let error {
            print("[WatchConnectivity] Activation error: \(error)")
        } else {
            print(
                "[WatchConnectivity] Activated: \(activationState.rawValue)"
            )
        }

        // Check for previously received context (e.g., ACK)
        let context = session.receivedApplicationContext
        if let syncedId = context["lastSyncedSessionId"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.lastSyncedSessionId = syncedId
                self?.transferState = .synced
            }
            offlineStore.remove(sessionId: syncedId)
        }

        // Sync any sessions queued while the app was not running
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.syncAllOfflineSessions()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable

            if session.isReachable {
                if self?.pendingSessionJSON != nil {
                    self?.retryPendingTransferIfNeeded()
                } else {
                    self?.syncAllOfflineSessions()
                }
            }
        }
        print(
            "[WatchConnectivity] Reachability: \(session.isReachable)"
        )
    }

    /// Receive application context from the phone (ACK, settings).
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let syncedId = applicationContext["lastSyncedSessionId"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.lastSyncedSessionId = syncedId
                self?.transferState = .synced
                self?.pendingSessionJSON = nil
                self?.retryCount = 0
            }
            offlineStore.remove(sessionId: syncedId)
            print("[WatchConnectivity] ACK received: \(syncedId)")

            // After removing the ACK'd session, sync the next pending one
            syncNextOfflineSession()
        }
    }

    /// Called when a file transfer finishes (success or failure).
    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        if let error {
            print("[WatchConnectivity] File transfer failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.transferState = .failed

                // Retry with exponential backoff
                let delay = min(Double(1 << (self?.retryCount ?? 0)), 30.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.retryPendingTransferIfNeeded()
                }
            }
        } else {
            print("[WatchConnectivity] File transfer completed")
            // Note: .synced is set when the phone sends ACK, not just
            // when the transfer completes. The file may have been delivered
            // but the phone hasn't processed it yet.
        }
    }

    /// Receive interactive messages from the phone.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchConnectivity] Message received: \(message)")
    }
}
