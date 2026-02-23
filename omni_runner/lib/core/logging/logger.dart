import 'dart:developer' as dev;

/// Log severity levels, ordered from lowest to highest.
enum LogLevel { debug, info, warn, error }

/// Structured logger for the application.
///
/// Uses `dart:developer` log() which appears in DevTools but is stripped
/// from release builds (unlike `print()`). Future integration with Sentry
/// can hook into [error] calls via a custom handler.
///
/// Usage:
/// ```dart
/// AppLogger.info('Session started', tag: 'TrackingBloc');
/// AppLogger.error('Upload failed', tag: 'SyncService', error: e);
/// ```
abstract final class AppLogger {
  /// Minimum level to emit. Messages below this are silently dropped.
  /// Change to [LogLevel.warn] for release builds if needed.
  static LogLevel minLevel = LogLevel.debug;

  /// Optional hook for external error reporting (e.g. Sentry).
  /// Called for every [error] log. Set during app initialization.
  static void Function(String message, Object? error, StackTrace? stack)?
      onError;

  static void debug(String msg, {String tag = 'App'}) =>
      _log(LogLevel.debug, msg, tag: tag);

  static void info(String msg, {String tag = 'App'}) =>
      _log(LogLevel.info, msg, tag: tag);

  static void warn(String msg, {String tag = 'App'}) =>
      _log(LogLevel.warn, msg, tag: tag);

  static void error(
    String msg, {
    String tag = 'App',
    Object? error,
    StackTrace? stack,
  }) {
    _log(LogLevel.error, msg, tag: tag, error: error, stack: stack);
    onError?.call(msg, error, stack);
  }

  static void _log(
    LogLevel level,
    String msg, {
    required String tag,
    Object? error,
    StackTrace? stack,
  }) {
    if (level.index < minLevel.index) return;
    final prefix = level.name.toUpperCase().padRight(5);
    dev.log(
      '[$prefix] $msg',
      name: tag,
      level: level.index * 300 + 500,
      error: error,
      stackTrace: stack,
    );
  }
}
