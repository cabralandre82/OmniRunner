import 'dart:async';
import 'dart:math';

/// Retries an async operation with exponential backoff.
///
/// [action]     — the async function to attempt.
/// [maxAttempts] — total number of tries (default 3).
/// [baseDelay]  — initial delay before the first retry (default 500 ms).
/// [retryIf]    — optional predicate; only retry when it returns `true` for
///                the caught exception. Defaults to retrying on all exceptions.
///
/// Throws the last exception if all attempts fail.
Future<T> retry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(milliseconds: 500),
  bool Function(Exception)? retryIf,
}) async {
  final rng = Random();
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action();
    } on Exception catch (e) {
      if (attempt == maxAttempts) rethrow;
      if (retryIf != null && !retryIf(e)) rethrow;

      // Exponential backoff with jitter: base * 2^(attempt-1) + random jitter
      final delayMs = baseDelay.inMilliseconds * (1 << (attempt - 1));
      final jitter = rng.nextInt(delayMs ~/ 2 + 1);
      await Future<void>.delayed(Duration(milliseconds: delayMs + jitter));
    }
  }

  // Unreachable — kept for type safety.
  throw StateError('retry: exhausted $maxAttempts attempts');
}
