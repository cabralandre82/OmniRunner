import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Configuration for the Android foreground service used during GPS tracking.
///
/// Infrastructure layer. Not exposed to domain.
/// Wraps [flutter_foreground_task] plugin configuration.
///
/// This ensures the Android process stays alive when:
/// - Screen is off
/// - App is in background
/// - User switches to another app
abstract final class ForegroundTaskConfig {
  /// Notification channel ID for run tracking.
  static const _channelId = 'omni_runner_tracking';

  /// Initialize the foreground task with run-tracking notification.
  ///
  /// Must be called once at app startup (in main.dart or service locator).
  /// Does nothing on iOS (plugin is Android-only for foreground service).
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Run Tracking',
        channelDescription: 'Keeps GPS tracking active during your run',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start the foreground service with persistent notification.
  ///
  /// Call when a workout session starts.
  /// On Android: shows persistent notification, prevents process kill.
  /// On iOS: no-op (background mode handled via Info.plist).
  static Future<ServiceRequestResult> start() {
    return FlutterForegroundTask.startService(
      serviceId: 1,
      notificationTitle: 'Omni Runner — Corrida em andamento',
      notificationText: 'Rastreamento GPS ativo',
    );
  }

  /// Update the notification text with live stats.
  ///
  /// Call periodically during the workout to show current distance/pace.
  /// Example: title="Running — 3.2 km", body="Pace: 5:30 /km"
  static Future<ServiceRequestResult> updateNotification({
    required String title,
    required String body,
  }) {
    return FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: body,
    );
  }

  /// Stop the foreground service and remove notification.
  ///
  /// Call when the workout session ends (completed, paused, or discarded).
  static Future<ServiceRequestResult> stop() {
    return FlutterForegroundTask.stopService();
  }
}
