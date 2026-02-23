import 'dart:async';

import 'package:flutter/services.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/watch_bridge/watch_session_payload.dart';

/// Dart-side bridge to native watch connectivity.
///
/// Listens on MethodChannel `"omnirunner/watch"` for events from:
/// - iOS: `PhoneConnectivityManager.swift` (WatchConnectivity)
/// - Android: `PhoneDataLayerManager.kt` (DataLayer API)
///
/// Exposes typed streams that the rest of the app can subscribe to:
/// - [onSessionReceived] — full workout session from the watch
/// - [onLiveSample]      — periodic HR/pace/distance snapshot
/// - [onWatchStateChanged] — workout state transitions
/// - [onReachabilityChanged] — watch connection status
///
/// Also provides methods to call back into native:
/// - [acknowledgeSession] — ACK a processed session
/// - [getWatchStatus]     — query current watch state
///
/// Architecture reference: docs/WatchArchitecture.md §6
class WatchBridge {
  WatchBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('omnirunner/watch');

  static const _tag = 'WatchBridge';
  final MethodChannel _channel;

  // ── Streams (Native → Dart) ───────────────────────────────────

  final _sessionController =
      StreamController<WatchSessionPayload>.broadcast();
  final _liveSampleController =
      StreamController<WatchLiveSample>.broadcast();
  final _stateController =
      StreamController<WatchWorkoutState>.broadcast();
  final _reachabilityController = StreamController<bool>.broadcast();

  /// Full workout session received from the watch.
  ///
  /// Emitted once per workout, after the user ends the workout on the watch.
  /// Contains GPS points, HR samples, and session metadata.
  Stream<WatchSessionPayload> get onSessionReceived =>
      _sessionController.stream;

  /// Periodic live sample during an active watch workout.
  ///
  /// Emitted every ~5 seconds while the watch is tracking.
  /// Used for real-time display on the phone — NOT persisted.
  Stream<WatchLiveSample> get onLiveSample => _liveSampleController.stream;

  /// Watch workout state changes (running, paused, ended).
  Stream<WatchWorkoutState> get onWatchStateChanged =>
      _stateController.stream;

  /// Watch reachability changes (connected / disconnected).
  Stream<bool> get onReachabilityChanged =>
      _reachabilityController.stream;

  // ── Lifecycle ─────────────────────────────────────────────────

  /// Start listening for events from native watch bridge.
  ///
  /// Call once at app startup (e.g., from `main.dart` or a service locator).
  void init() {
    _channel.setMethodCallHandler(_handleNativeCall);
    AppLogger.info('Initialized — listening on omnirunner/watch', tag: _tag);
  }

  /// Stop listening and close all streams.
  ///
  /// Call when the bridge is no longer needed.
  void dispose() {
    _channel.setMethodCallHandler(null);
    _sessionController.close();
    _liveSampleController.close();
    _stateController.close();
    _reachabilityController.close();
    AppLogger.info('Disposed', tag: _tag);
  }

  // ── Methods (Dart → Native) ───────────────────────────────────

  /// Acknowledge that a session has been processed and persisted.
  ///
  /// This sends an ACK back to the watch so it can mark the session
  /// as synced and free local storage.
  Future<void> acknowledgeSession(String sessionId) async {
    try {
      await _channel.invokeMethod<void>(
        'acknowledgeSession',
        {'sessionId': sessionId},
      );
      AppLogger.debug('ACK sent for session: $sessionId', tag: _tag);
    } on PlatformException catch (e) {
      AppLogger.warn('ACK failed: ${e.message}', tag: _tag);
    }
  }

  /// Query the current watch connectivity status.
  ///
  /// Returns a map with platform-specific status fields:
  /// - `isSupported`, `isReachable`, `isPaired`, etc.
  Future<Map<String, dynamic>> getWatchStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getWatchStatus',
      );
      return result ?? {};
    } on PlatformException catch (e) {
      AppLogger.warn('getWatchStatus failed: ${e.message}', tag: _tag);
      return {'error': e.message};
    }
  }

  // ── Private: MethodCall Handler ───────────────────────────────

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final args = call.arguments;

    switch (call.method) {
      case 'onSessionReceived':
        _handleSessionReceived(args);
      case 'onLiveSample':
        _handleLiveSample(args);
      case 'onWatchStateChanged':
        _handleWatchStateChanged(args);
      case 'onReachabilityChanged':
        _handleReachabilityChanged(args);
      default:
        AppLogger.warn('Unknown method: ${call.method}', tag: _tag);
    }
  }

  void _handleSessionReceived(dynamic args) {
    if (args is! Map) {
      AppLogger.warn('onSessionReceived: invalid args type', tag: _tag);
      return;
    }

    final payload = WatchSessionPayload.tryParse(args);
    if (payload == null) {
      AppLogger.warn('onSessionReceived: failed to parse payload', tag: _tag);
      return;
    }

    AppLogger.info(
      'Session received: ${payload.sessionId} '
      '(${payload.source}, ${payload.points.length} GPS, '
      '${payload.hrSamples.length} HR)',
      tag: _tag,
    );

    _sessionController.add(payload);
  }

  void _handleLiveSample(dynamic args) {
    if (args is! Map) return;

    final sample = WatchLiveSample.tryParse(args);
    if (sample == null) return;

    _liveSampleController.add(sample);
  }

  void _handleWatchStateChanged(dynamic args) {
    if (args is! Map) return;

    final state = WatchWorkoutState.tryParse(args);
    if (state == null) return;

    AppLogger.debug(
      'Watch state: ${state.state} (session=${state.sessionId})',
      tag: _tag,
    );

    _stateController.add(state);
  }

  void _handleReachabilityChanged(dynamic args) {
    if (args is! Map) return;

    final isReachable = args['isReachable'] as bool? ?? false;
    AppLogger.debug('Reachability: $isReachable', tag: _tag);
    _reachabilityController.add(isReachable);
  }
}
