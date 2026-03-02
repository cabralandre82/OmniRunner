import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';

/// Automatically syncs pending sessions when connectivity is restored.
///
/// - Runs an initial sync attempt on [init]
/// - Subscribes to [Connectivity.onConnectivityChanged]
/// - When connection transitions from none → any, triggers [ISyncRepo.syncPending]
/// - Cooldown prevents repeated sync calls within [_cooldown]
///
/// Call [dispose] on app teardown to cancel the subscription.
class AutoSyncManager {
  static const _tag = 'AutoSync';
  static const _cooldown = Duration(seconds: 30);

  final ISyncRepo _syncRepo;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wasDisconnected = false;
  bool _syncing = false;

  AutoSyncManager({
    required ISyncRepo syncRepo,
    Connectivity? connectivity,
  })  : _syncRepo = syncRepo,
        _connectivity = connectivity ?? Connectivity();

  /// Start listening for connectivity changes and trigger initial sync.
  Future<void> init() async {
    // Initial sync attempt (fire-and-forget, non-blocking).
    unawaited(_trySync('app_start'));

    // Seed the disconnected state.
    try {
      final current = await _connectivity.checkConnectivity();
      _wasDisconnected = current.every((r) => r == ConnectivityResult.none);
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'AutoSyncManager', error: e);
      _wasDisconnected = false;
    }

    _sub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    AppLogger.info('AutoSync initialized', tag: _tag);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);

    if (connected && _wasDisconnected) {
      AppLogger.info('Connectivity restored — triggering sync', tag: _tag);
      unawaited(_trySync('connectivity_restored'));
    }

    _wasDisconnected = !connected;
  }

  Future<void> _trySync(String reason) async {
    if (_syncing) return;

    final now = DateTime.now();
    if (now.difference(_lastSyncAt) < _cooldown) {
      AppLogger.debug('Sync skipped (cooldown): $reason', tag: _tag);
      return;
    }

    _syncing = true;
    _lastSyncAt = now;

    try {
      AppLogger.info('Auto-sync triggered ($reason)', tag: _tag);
      final failure = await _syncRepo.syncPending();
      if (failure != null) {
        AppLogger.debug('Auto-sync result: ${failure.runtimeType}', tag: _tag);
      }
    } on Exception catch (e) {
      AppLogger.warn('Auto-sync error: $e', tag: _tag);
    } finally {
      _syncing = false;
    }
  }

  /// Cancel the connectivity subscription.
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
