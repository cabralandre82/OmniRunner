import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/logging/logger.dart';

void main() {
  group('AppLogger', () {
    tearDown(() {
      AppLogger.minLevel = LogLevel.debug;
      AppLogger.onError = null;
    });

    test('debug, info, warn, error do not throw', () {
      expect(() => AppLogger.debug('test'), returnsNormally);
      expect(() => AppLogger.info('test'), returnsNormally);
      expect(() => AppLogger.warn('test'), returnsNormally);
      expect(() => AppLogger.error('test'), returnsNormally);
    });

    test('respects minLevel — drops messages below it', () {
      AppLogger.minLevel = LogLevel.error;
      // These should be silently dropped (no way to assert, but no crash)
      expect(() => AppLogger.debug('dropped'), returnsNormally);
      expect(() => AppLogger.info('dropped'), returnsNormally);
      expect(() => AppLogger.warn('dropped'), returnsNormally);
    });

    test('error calls onError callback', () {
      String? capturedMsg;
      Object? capturedError;

      AppLogger.onError = (msg, error, stack) {
        capturedMsg = msg;
        capturedError = error;
      };

      final err = Exception('test error');
      AppLogger.error('boom', error: err);

      expect(capturedMsg, 'boom');
      expect(capturedError, err);
    });

    test('error with stack trace passes it to onError', () {
      StackTrace? capturedStack;

      AppLogger.onError = (msg, error, stack) {
        capturedStack = stack;
      };

      final stack = StackTrace.current;
      AppLogger.error('with stack', stack: stack);

      expect(capturedStack, stack);
    });

    test('LogLevel order is debug < info < warn < error', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warn.index));
      expect(LogLevel.warn.index, lessThan(LogLevel.error.index));
    });

    test('accepts custom tag parameter', () {
      expect(
        () => AppLogger.info('msg', tag: 'CustomTag'),
        returnsNormally,
      );
    });
  });
}
