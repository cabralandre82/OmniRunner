import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/wearables_ble/ble_reconnect_manager.dart';

void main() {
  group('BleReconnectManager', () {
    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /// Creates a manager with instant delays so tests run fast.
    BleReconnectManager createManager({
      required Future<bool> Function() action,
      int maxAttempts = 5,
    }) {
      return BleReconnectManager(
        reconnectAction: action,
        maxAttempts: maxAttempts,
        baseDelay: Duration.zero,
        maxDelay: Duration.zero,
      );
    }

    // -----------------------------------------------------------------------
    // delayForAttempt (exponential backoff)
    // -----------------------------------------------------------------------

    group('delayForAttempt', () {
      test('attempt 0 returns base delay', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
        );

        expect(mgr.delayForAttempt(0), const Duration(seconds: 1));
      });

      test('attempt 1 doubles', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
        );

        expect(mgr.delayForAttempt(1), const Duration(seconds: 2));
      });

      test('attempt 2 = 4x base', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
        );

        expect(mgr.delayForAttempt(2), const Duration(seconds: 4));
      });

      test('attempt 3 = 8x base', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
        );

        expect(mgr.delayForAttempt(3), const Duration(seconds: 8));
      });

      test('caps at maxDelay', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
        );

        // 2^5 = 32s > 30s cap
        expect(mgr.delayForAttempt(5), const Duration(seconds: 30));
      });

      test('very high attempt stays at cap', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 1),
          maxDelay: const Duration(seconds: 30),
        );

        expect(mgr.delayForAttempt(20), const Duration(seconds: 30));
      });

      test('with 2s base, attempt 0 = 2s', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 2),
          maxDelay: const Duration(minutes: 1),
        );

        expect(mgr.delayForAttempt(0), const Duration(seconds: 2));
      });

      test('with 2s base, attempt 3 = 16s', () {
        final mgr = BleReconnectManager(
          reconnectAction: () async => true,
          baseDelay: const Duration(seconds: 2),
          maxDelay: const Duration(minutes: 1),
        );

        expect(mgr.delayForAttempt(3), const Duration(seconds: 16));
      });
    });

    // -----------------------------------------------------------------------
    // Initial state
    // -----------------------------------------------------------------------

    group('initial state', () {
      test('isActive is false', () {
        final mgr = createManager(action: () async => true);
        expect(mgr.isActive, isFalse);
      });

      test('currentAttempt is 0', () {
        final mgr = createManager(action: () async => true);
        expect(mgr.currentAttempt, 0);
      });
    });

    // -----------------------------------------------------------------------
    // start / cancel
    // -----------------------------------------------------------------------

    group('start and cancel', () {
      test('start sets isActive to true', () {
        final mgr = createManager(action: () async => true);
        mgr.start();
        expect(mgr.isActive, isTrue);
        mgr.dispose();
      });

      test('cancel resets isActive', () {
        final mgr = createManager(action: () async => false);
        mgr.start();
        mgr.cancel();
        expect(mgr.isActive, isFalse);
        expect(mgr.currentAttempt, 0);
      });

      test('double start is a no-op', () {
        final mgr = createManager(
          action: () async => false,
        );
        mgr.start();
        mgr.start(); // should not reset
        expect(mgr.isActive, isTrue);
        mgr.dispose();
      });

      test('start after dispose is a no-op', () {
        final mgr = createManager(action: () async => true);
        mgr.dispose();
        mgr.start();
        expect(mgr.isActive, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // Successful reconnection
    // -----------------------------------------------------------------------

    group('successful reconnection', () {
      test('calls onReconnected on first success', () async {
        final completer = Completer<void>();
        final mgr = createManager(action: () async => true);
        mgr.onReconnected = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));

        expect(mgr.isActive, isFalse);
        expect(mgr.currentAttempt, 0);
        mgr.dispose();
      });

      test('succeeds on third attempt', () async {
        int calls = 0;
        final completer = Completer<void>();

        final mgr = createManager(
          action: () async {
            calls++;
            return calls >= 3;
          },
        );
        mgr.onReconnected = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));

        expect(calls, 3);
        expect(mgr.isActive, isFalse);
        mgr.dispose();
      });

      test('resets attempt counter after success', () async {
        final completer = Completer<void>();
        final mgr = createManager(action: () async => true);
        mgr.onReconnected = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));
        expect(mgr.currentAttempt, 0);
        mgr.dispose();
      });
    });

    // -----------------------------------------------------------------------
    // Exhausted attempts
    // -----------------------------------------------------------------------

    group('exhausted attempts', () {
      test('calls onGaveUp after maxAttempts', () async {
        final completer = Completer<void>();
        int calls = 0;

        final mgr = createManager(
          action: () async {
            calls++;
            return false;
          },
          maxAttempts: 3,
        );
        mgr.onGaveUp = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));

        expect(calls, 3);
        expect(mgr.isActive, isFalse);
        mgr.dispose();
      });

      test('is not active after giving up', () async {
        final completer = Completer<void>();
        final mgr = createManager(
          action: () async => false,
          maxAttempts: 1,
        );
        mgr.onGaveUp = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));
        expect(mgr.isActive, isFalse);
        mgr.dispose();
      });

      test('single attempt manager', () async {
        final completer = Completer<void>();
        int calls = 0;

        final mgr = createManager(
          action: () async {
            calls++;
            return false;
          },
          maxAttempts: 1,
        );
        mgr.onGaveUp = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));
        expect(calls, 1);
        mgr.dispose();
      });
    });

    // -----------------------------------------------------------------------
    // Exception handling
    // -----------------------------------------------------------------------

    group('action throws exception', () {
      test('continues retrying after exception', () async {
        int calls = 0;
        final completer = Completer<void>();

        final mgr = createManager(
          action: () async {
            calls++;
            if (calls < 3) throw Exception('BLE error');
            return true;
          },
        );
        mgr.onReconnected = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));
        expect(calls, 3);
        mgr.dispose();
      });

      test('gives up after maxAttempts even with exceptions', () async {
        int calls = 0;
        final completer = Completer<void>();

        final mgr = createManager(
          action: () async {
            calls++;
            throw Exception('fail');
          },
          maxAttempts: 2,
        );
        mgr.onGaveUp = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));
        expect(calls, 2);
        mgr.dispose();
      });
    });

    // -----------------------------------------------------------------------
    // onRetry callback
    // -----------------------------------------------------------------------

    group('onRetry callback', () {
      test('fires before each attempt with correct data', () async {
        final retries = <(int, Duration)>[];
        final completer = Completer<void>();
        int calls = 0;

        final mgr = createManager(
          action: () async {
            calls++;
            return calls >= 3;
          },
          maxAttempts: 5,
        );
        mgr.onRetry = (attempt, delay) => retries.add((attempt, delay));
        mgr.onReconnected = completer.complete;
        mgr.start();

        await completer.future.timeout(const Duration(seconds: 2));

        expect(retries.length, 3);
        expect(retries[0].$1, 0);
        expect(retries[1].$1, 1);
        expect(retries[2].$1, 2);
        mgr.dispose();
      });
    });

    // -----------------------------------------------------------------------
    // Cancel during active cycle
    // -----------------------------------------------------------------------

    group('cancel during active cycle', () {
      test('stops further attempts', () async {
        int calls = 0;
        final firstAttempt = Completer<void>();

        final mgr = createManager(
          action: () async {
            calls++;
            if (calls == 1) firstAttempt.complete();
            return false;
          },
          maxAttempts: 10,
        );
        mgr.start();

        await firstAttempt.future.timeout(const Duration(seconds: 2));
        mgr.cancel();

        // Give time for any pending timers
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final callsAfterCancel = calls;
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(calls, callsAfterCancel);
        expect(mgr.isActive, isFalse);
        mgr.dispose();
      });
    });

    // -----------------------------------------------------------------------
    // Dispose
    // -----------------------------------------------------------------------

    group('dispose', () {
      test('prevents further starts', () {
        final mgr = createManager(action: () async => true);
        mgr.dispose();
        mgr.start();
        expect(mgr.isActive, isFalse);
      });

      test('cancels active cycle', () {
        final mgr = createManager(action: () async => false);
        mgr.start();
        expect(mgr.isActive, isTrue);
        mgr.dispose();
        expect(mgr.isActive, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // Can restart after completion
    // -----------------------------------------------------------------------

    group('restart after completion', () {
      test('can restart after successful reconnection', () async {
        int calls = 0;
        Completer<void> completer = Completer<void>();

        final mgr = createManager(action: () async {
          calls++;
          return true;
        });
        mgr.onReconnected = () {
          if (!completer.isCompleted) completer.complete();
        };

        // First cycle
        mgr.start();
        await completer.future.timeout(const Duration(seconds: 2));
        expect(mgr.isActive, isFalse);

        // Second cycle
        calls = 0;
        completer = Completer<void>();
        mgr.onReconnected = () {
          if (!completer.isCompleted) completer.complete();
        };
        mgr.start();
        await completer.future.timeout(const Duration(seconds: 2));
        expect(calls, 1);
        mgr.dispose();
      });

      test('can restart after giving up', () async {
        int calls = 0;
        Completer<void> completer = Completer<void>();

        final mgr = createManager(
          action: () async {
            calls++;
            return false;
          },
          maxAttempts: 2,
        );
        mgr.onGaveUp = () {
          if (!completer.isCompleted) completer.complete();
        };

        // First cycle
        mgr.start();
        await completer.future.timeout(const Duration(seconds: 2));
        expect(mgr.isActive, isFalse);

        // Second cycle
        calls = 0;
        completer = Completer<void>();
        mgr.onGaveUp = () {
          if (!completer.isCompleted) completer.complete();
        };
        mgr.start();
        await completer.future.timeout(const Duration(seconds: 2));
        expect(calls, 2);
        mgr.dispose();
      });

      test('can restart after cancel', () async {
        final completer = Completer<void>();

        final mgr = createManager(action: () async {
          return true;
        });

        mgr.start();
        mgr.cancel();

        mgr.onReconnected = () {
          if (!completer.isCompleted) completer.complete();
        };
        mgr.start();
        await completer.future.timeout(const Duration(seconds: 2));
        expect(mgr.isActive, isFalse);
        mgr.dispose();
      });
    });
  });
}
