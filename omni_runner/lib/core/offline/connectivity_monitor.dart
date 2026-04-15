import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/offline/offline_queue.dart';

/// Listens for connectivity changes and replays the offline queue when
/// connectivity is restored.
///
/// When offline, a periodic health check (every 60s) pings Supabase to
/// detect when the service is reachable again, even if the OS connectivity
/// event fires before Supabase is truly available.
class ConnectivityMonitor {
  final OfflineQueue _queue;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _healthCheckTimer;
  bool _wasOffline = false;
  bool _replayInProgress = false;

  ConnectivityMonitor({
    required OfflineQueue queue,
    Connectivity? connectivity,
  })  : _queue = queue,
        _connectivity = connectivity ?? Connectivity();

  /// Start listening for connectivity changes. Call from app init.
  void start() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen(_onChange);
  }

  /// Stop listening. Call when disposing.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  void _onChange(List<ConnectivityResult> results) async {
    final isOffline = results.every((r) =>
        r == ConnectivityResult.none || r == ConnectivityResult.other);
    final wasOffline = _wasOffline;
    _wasOffline = isOffline;

    if (isOffline && !wasOffline) {
      _startHealthCheck();
    }

    if (wasOffline && !isOffline) {
      _stopHealthCheck();
      await _replayQueue();
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _pingSupabase(),
    );
    AppLogger.info('ConnectivityMonitor: started periodic health check',
        tag: 'ConnectivityMonitor');
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _pingSupabase() async {
    try {
      await sl<SupabaseClient>()
          .from('profiles')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 10));

      AppLogger.info('ConnectivityMonitor: Supabase reachable again via health check',
          tag: 'ConnectivityMonitor');
      _wasOffline = false;
      _stopHealthCheck();
      await _replayQueue();
    } on Object catch (_) {
      AppLogger.debug('ConnectivityMonitor: health check failed, still offline',
          tag: 'ConnectivityMonitor');
    }
  }

  Future<void> _replayQueue() async {
    if (_replayInProgress) return;
    _replayInProgress = true;
    try {
      AppLogger.info('ConnectivityMonitor: connectivity restored, replaying queue',
          tag: 'ConnectivityMonitor');
      final count = await _queue.replay();
      if (count > 0) {
        AppLogger.info('ConnectivityMonitor: replayed $count queued operations',
            tag: 'ConnectivityMonitor');
      }
    } on Object catch (e, st) {
      AppLogger.error('ConnectivityMonitor: replay failed', error: e, stack: st);
    } finally {
      _replayInProgress = false;
    }
  }

  /// Manually trigger replay (e.g. from a retry button when connectivity
  /// listener is not desired).
  Future<int> replayNow() => _queue.replayNow();
}
