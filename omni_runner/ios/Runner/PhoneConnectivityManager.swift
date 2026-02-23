import Foundation
import Flutter
import WatchConnectivity

/// Manages WatchConnectivity on the **phone (iPhone) side**.
///
/// Responsibilities:
/// - Activate `WCSession` as delegate
/// - Receive full workout sessions from watch (file transfer)
/// - Receive live samples from watch (interactive message)
/// - Forward data to Flutter via `MethodChannel("omnirunner/watch")`
/// - Send ACK back to watch via `applicationContext`
///
/// Architecture reference: docs/WatchArchitecture.md §6
final class PhoneConnectivityManager: NSObject, WCSessionDelegate {

    /// MethodChannel for communicating with Flutter.
    private var channel: FlutterMethodChannel?

    /// Singleton — initialized once from AppDelegate.
    static let shared = PhoneConnectivityManager()

    // MARK: - Setup

    /// Configure the MethodChannel and activate WCSession.
    ///
    /// Call from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func setup(with binaryMessenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "omnirunner/watch",
            binaryMessenger: binaryMessenger
        )

        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handleFlutterCall(call, result: result)
        }

        guard WCSession.isSupported() else {
            print("[PhoneConnectivity] WCSession not supported")
            return
        }

        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Flutter → Native Method Calls

    private func handleFlutterCall(
        _ call: FlutterMethodCall, result: @escaping FlutterResult
    ) {
        switch call.method {
        case "acknowledgeSession":
            guard let args = call.arguments as? [String: Any],
                  let sessionId = args["sessionId"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGS",
                        message: "sessionId required",
                        details: nil
                    )
                )
                return
            }
            acknowledgeSession(sessionId)
            result(nil)

        case "getWatchStatus":
            let status: [String: Any] = [
                "isSupported": WCSession.isSupported(),
                "isReachable": WCSession.isSupported()
                    ? WCSession.default.isReachable : false,
                "isPaired": WCSession.isSupported()
                    ? WCSession.default.isPaired : false,
                "isWatchAppInstalled": WCSession.isSupported()
                    ? WCSession.default.isWatchAppInstalled : false,
                "activationState": WCSession.isSupported()
                    ? WCSession.default.activationState.rawValue : 0,
            ]
            result(status)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - ACK to Watch

    /// Tell the watch we've received and processed a session.
    ///
    /// Uses `updateApplicationContext()` which overwrites previous context.
    private func acknowledgeSession(_ sessionId: String) {
        guard WCSession.default.activationState == .activated else { return }

        do {
            try WCSession.default.updateApplicationContext([
                "lastSyncedSessionId": sessionId
            ])
            print("[PhoneConnectivity] ACK sent: \(sessionId)")
        } catch {
            print("[PhoneConnectivity] ACK error: \(error)")
        }
    }

    // MARK: - WCSessionDelegate Required

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("[PhoneConnectivity] Activation error: \(error)")
        } else {
            print(
                "[PhoneConnectivity] Activated: \(activationState.rawValue)"
                    + ", paired: \(session.isPaired)"
                    + ", installed: \(session.isWatchAppInstalled)"
            )
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[PhoneConnectivity] Session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[PhoneConnectivity] Session deactivated — reactivating")
        WCSession.default.activate()
    }

    // MARK: - Receive File Transfer (Full Session)

    func session(
        _ session: WCSession,
        didReceive file: WCSessionFile
    ) {
        guard let metadata = file.metadata,
              let type = metadata["type"] as? String,
              type == "workout_session"
        else {
            print("[PhoneConnectivity] Unknown file received")
            return
        }

        let sessionId = metadata["sessionId"] as? String ?? "unknown"

        do {
            let data = try Data(contentsOf: file.fileURL)
            guard let json = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any] else {
                print("[PhoneConnectivity] Invalid JSON in file")
                return
            }

            print(
                "[PhoneConnectivity] Session received: \(sessionId)"
                    + " (\(data.count) bytes)"
            )

            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod(
                    "onSessionReceived", arguments: json
                )
            }
        } catch {
            print("[PhoneConnectivity] File read error: \(error)")
        }
    }

    // MARK: - Receive Interactive Messages (Live Samples)

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let type = message["type"] as? String else { return }

        switch type {
        case "live_sample":
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod(
                    "onLiveSample", arguments: message
                )
            }

        default:
            print("[PhoneConnectivity] Unknown message type: \(type)")
        }
    }

    // MARK: - Receive Application Context (Watch State Updates)

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let type = applicationContext["type"] as? String,
           type == "workout_state"
        {
            DispatchQueue.main.async { [weak self] in
                self?.channel?.invokeMethod(
                    "onWatchStateChanged", arguments: applicationContext
                )
            }
        }
    }

    // MARK: - Reachability Changes

    func sessionReachabilityDidChange(_ session: WCSession) {
        let status: [String: Any] = [
            "isReachable": session.isReachable,
        ]
        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(
                "onReachabilityChanged", arguments: status
            )
        }
    }
}
