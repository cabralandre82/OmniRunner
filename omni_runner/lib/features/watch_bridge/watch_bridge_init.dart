import 'dart:async';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/features/watch_bridge/process_watch_session.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge.dart';
import 'package:omni_runner/features/watch_bridge/watch_session_payload.dart';

const _tag = 'WatchBridgeInit';

/// Subscription handles so the caller can cancel them on app teardown.
StreamSubscription<void>? _sessionSub;
StreamSubscription<void>? _reachabilitySub;

/// Sessions that failed processing and need retry.
///
/// Key = sessionId, Value = payload. Cleared on successful processing.
/// Limited to [_maxPendingRetries] entries to avoid unbounded memory.
final Map<String, WatchSessionPayload> _pendingRetries = {};

/// Maximum number of sessions queued for retry.
const int _maxPendingRetries = 10;

/// Maximum retry attempts per session before giving up.
const int _maxRetryAttempts = 3;

/// Tracks retry attempt count per session.
final Map<String, int> _retryAttempts = {};

/// Whether a retry cycle is currently running (prevents concurrent retries).
bool _retrying = false;

/// Initialize the watch bridge and start auto-processing incoming sessions.
///
/// Call once after [setupServiceLocator] completes.
///
/// Flow:
/// 1. `WatchBridge.init()` — registers the MethodChannel handler
/// 2. Subscribes `onSessionReceived` → `ProcessWatchSession`
///    so every incoming watch session is automatically persisted + ACK'd.
/// 3. Subscribes `onReachabilityChanged` — retries pending sessions
///    when the watch reconnects.
void initWatchBridge() {
  final bridge = sl<WatchBridge>();
  final processSession = sl<ProcessWatchSession>();

  bridge.init();

  _sessionSub = bridge.onSessionReceived.listen((payload) {
    AppLogger.info(
      'Auto-processing session: ${payload.sessionId}',
      tag: _tag,
    );
    _processWithRetry(processSession, payload);
  });

  _reachabilitySub = bridge.onReachabilityChanged.listen((isReachable) {
    if (isReachable && _pendingRetries.isNotEmpty) {
      AppLogger.info(
        'Watch reconnected — retrying '
        '${_pendingRetries.length} pending session(s)',
        tag: _tag,
      );
      _retryPendingSessions(processSession);
    }
  });

  AppLogger.info('Watch bridge ready — auto-processing enabled', tag: _tag);
}

/// Process a session, adding to retry queue on failure.
Future<void> _processWithRetry(
  ProcessWatchSession processSession,
  WatchSessionPayload payload,
) async {
  final ok = await processSession(payload);

  if (ok) {
    _pendingRetries.remove(payload.sessionId);
    _retryAttempts.remove(payload.sessionId);
  } else {
    _enqueueForRetry(payload);
  }
}

/// Add a session to the retry queue.
void _enqueueForRetry(WatchSessionPayload payload) {
  if (_pendingRetries.length >= _maxPendingRetries) {
    AppLogger.warn(
      'Retry queue full ($_maxPendingRetries) — dropping oldest',
      tag: _tag,
    );
    final oldest = _pendingRetries.keys.first;
    _pendingRetries.remove(oldest);
    _retryAttempts.remove(oldest);
  }

  _pendingRetries[payload.sessionId] = payload;
  _retryAttempts.putIfAbsent(payload.sessionId, () => 0);

  AppLogger.debug(
    'Queued for retry: ${payload.sessionId} '
    '(${_pendingRetries.length} pending)',
    tag: _tag,
  );
}

/// Retry all pending sessions. Called on reconnection.
///
/// Processes sequentially to avoid flooding the database.
/// Guard against concurrent calls with [_retrying].
Future<void> _retryPendingSessions(
  ProcessWatchSession processSession,
) async {
  if (_retrying) return;
  _retrying = true;

  try {
    final entries = Map.of(_pendingRetries);

    for (final entry in entries.entries) {
      final sessionId = entry.key;
      final payload = entry.value;
      final attempts = _retryAttempts[sessionId] ?? 0;

      if (attempts >= _maxRetryAttempts) {
        AppLogger.warn(
          'Giving up on $sessionId after $_maxRetryAttempts attempts',
          tag: _tag,
        );
        _pendingRetries.remove(sessionId);
        _retryAttempts.remove(sessionId);
        continue;
      }

      _retryAttempts[sessionId] = attempts + 1;

      AppLogger.debug(
        'Retrying $sessionId (attempt ${attempts + 1}/$_maxRetryAttempts)',
        tag: _tag,
      );

      final ok = await processSession(payload);

      if (ok) {
        _pendingRetries.remove(sessionId);
        _retryAttempts.remove(sessionId);
      }
    }
  } finally {
    _retrying = false;
  }
}

/// Tear down the watch bridge (optional — for testing or app shutdown).
void disposeWatchBridge() {
  _sessionSub?.cancel();
  _sessionSub = null;
  _reachabilitySub?.cancel();
  _reachabilitySub = null;
  _pendingRetries.clear();
  _retryAttempts.clear();
  _retrying = false;
  sl<WatchBridge>().dispose();
}
