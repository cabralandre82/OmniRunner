import 'dart:async';
import 'dart:math';

import 'package:omni_runner/core/logging/logger.dart';

const String _tag = 'BleReconnect';

/// Manages automatic BLE reconnection with exponential backoff.
///
/// Pure logic class — no BLE dependency. Receives a [reconnectAction] callback
/// that performs the actual BLE reconnect. Testable by injecting a fake action.
///
/// Backoff schedule: 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s...
/// Max attempts: configurable, default = 10.
class BleReconnectManager {
  /// Called to attempt a reconnection. Return `true` if successful.
  final Future<bool> Function() reconnectAction;

  /// Maximum number of reconnect attempts before giving up.
  final int maxAttempts;

  /// Base delay for exponential backoff.
  final Duration baseDelay;

  /// Maximum delay between attempts (cap for backoff).
  final Duration maxDelay;

  Timer? _timer;
  int _attempt = 0;
  bool _active = false;
  bool _disposed = false;

  /// Called when reconnection succeeds.
  void Function()? onReconnected;

  /// Called when all attempts are exhausted.
  void Function()? onGaveUp;

  /// Called each time a retry begins. Provides attempt number and delay.
  void Function(int attempt, Duration delay)? onRetry;

  BleReconnectManager({
    required this.reconnectAction,
    this.maxAttempts = 10,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  /// Whether a reconnection cycle is currently active.
  bool get isActive => _active;

  /// Current attempt number (0-based). Resets on [cancel] or success.
  int get currentAttempt => _attempt;

  /// Start the reconnection cycle. If already active, does nothing.
  void start() {
    if (_active || _disposed) return;
    _active = true;
    _attempt = 0;
    AppLogger.info('Reconnection started (max $maxAttempts attempts)', tag: _tag);
    _scheduleNext();
  }

  /// Cancel any pending reconnection. Safe to call if not active.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _active = false;
    _attempt = 0;
  }

  /// Dispose and prevent any future use.
  void dispose() {
    cancel();
    _disposed = true;
  }

  /// Compute the delay for the given attempt number.
  ///
  /// Exponential backoff: baseDelay * 2^attempt, capped at maxDelay.
  Duration delayForAttempt(int attempt) {
    final ms = baseDelay.inMilliseconds * pow(2, attempt);
    final capped = min(ms.toInt(), maxDelay.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  void _scheduleNext() {
    if (!_active || _disposed) return;

    if (_attempt >= maxAttempts) {
      AppLogger.warn(
        'Gave up after $maxAttempts attempts',
        tag: _tag,
      );
      _active = false;
      _attempt = 0;
      onGaveUp?.call();
      return;
    }

    final delay = delayForAttempt(_attempt);
    AppLogger.info(
      'Attempt ${_attempt + 1}/$maxAttempts in ${delay.inSeconds}s',
      tag: _tag,
    );
    onRetry?.call(_attempt, delay);

    _timer?.cancel();
    _timer = Timer(delay, _tryReconnect);
  }

  Future<void> _tryReconnect() async {
    if (!_active || _disposed) return;

    _attempt++;

    try {
      final success = await reconnectAction();

      if (!_active || _disposed) return;

      if (success) {
        AppLogger.info(
          'Reconnected on attempt $_attempt',
          tag: _tag,
        );
        _active = false;
        _attempt = 0;
        onReconnected?.call();
      } else {
        _scheduleNext();
      }
    } on Exception catch (e) {
      AppLogger.warn('Reconnect attempt $_attempt failed: $e', tag: _tag);
      if (_active && !_disposed) _scheduleNext();
    }
  }
}
