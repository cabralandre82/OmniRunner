import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Handles FCM/APNS push notification lifecycle:
///   1. Request permission (iOS prompts, Android auto-grants)
///   2. Obtain and persist FCM token to `device_tokens` table
///   3. Listen for token refresh and update the table
///   4. Handle foreground messages (log + optional callback)
///   5. Clean up token on sign-out
///
/// Relies on Firebase being initialized in `main.dart` before calling [init].
class PushNotificationService {
  static const _tag = 'PushNotifications';
  static const _table = 'device_tokens';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  /// Optional callback for foreground messages (e.g. show in-app banner).
  void Function(RemoteMessage message)? onForegroundMessage;

  /// Initialize push notifications. Call after Firebase.initializeApp().
  Future<void> init() async {
    try {
      // 1. Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        AppLogger.info('Push permission denied by user', tag: _tag);
        return;
      }

      AppLogger.info(
        'Push permission: ${settings.authorizationStatus.name}',
        tag: _tag,
      );

      // 2. Get and register token
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      // 3. Listen for token refresh
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(_registerToken);

      // 4. Foreground message handler
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 5. Background/terminated message handler (static, top-level)
      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

      AppLogger.info('Push notification service initialized', tag: _tag);
    } catch (e) {
      AppLogger.error(
        'Push init failed: $e',
        tag: _tag,
        error: e,
      );
    }
  }

  /// Register (upsert) device token in Supabase.
  Future<void> _registerToken(String token) async {
    if (!AppConfig.isSupabaseReady) return;

    final uid = sl<SupabaseClient>().auth.currentUser?.id;
    if (uid == null) return;

    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : 'web';

    try {
      await sl<SupabaseClient>().from(_table).upsert(
        {
          'user_id': uid,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
      AppLogger.info(
        'Device token registered ($platform)',
        tag: _tag,
      );
    } catch (e) {
      AppLogger.warn('Token registration failed: $e', tag: _tag);
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    AppLogger.debug(
      'Foreground push: ${message.notification?.title}',
      tag: _tag,
    );
    onForegroundMessage?.call(message);
  }

  /// Remove all device tokens for the current user (call on sign-out).
  Future<void> clearTokens() async {
    if (!AppConfig.isSupabaseReady) return;

    final uid = sl<SupabaseClient>().auth.currentUser?.id;
    if (uid == null) return;

    try {
      await sl<SupabaseClient>()
          .from(_table)
          .delete()
          .eq('user_id', uid);
      AppLogger.info('Device tokens cleared', tag: _tag);
    } catch (e) {
      AppLogger.warn('Token cleanup failed: $e', tag: _tag);
    }
  }

  /// Cancel listeners. Call when the service is no longer needed.
  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundSub?.cancel();
  }
}

/// Top-level background message handler (required by Firebase).
/// Must be a top-level function, not an instance method.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  AppLogger.debug(
    'Background push: ${message.notification?.title}',
    tag: 'PushBG',
  );
}
