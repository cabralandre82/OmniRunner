import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Lightweight, fire-and-forget product event tracker.
///
/// Writes to `product_events` table in Supabase. Events are append-only
/// and used for product analytics (onboarding funnel, first-use milestones,
/// flow abandonment). No PII beyond user_id.
///
/// For "first_*" events, use [trackOnce] which checks the DB before
/// inserting to avoid duplicates.
class ProductEventTracker {
  static const _tag = 'ProductEvents';
  static const _table = 'product_events';

  /// Track a product event (fire-and-forget).
  ///
  /// [eventName] — e.g. `onboarding_completed`, `flow_abandoned`.
  /// [properties] — arbitrary metadata (role, method, step, etc.).
  void track(String eventName, [Map<String, dynamic>? properties]) {
    _insert(eventName, properties);
  }

  /// Track an event only if the user hasn't triggered it before.
  ///
  /// Used for one-time milestones like `first_challenge_created`.
  void trackOnce(String eventName, [Map<String, dynamic>? properties]) {
    _insertOnce(eventName, properties);
  }

  Future<void> _insert(
    String eventName,
    Map<String, dynamic>? properties,
  ) async {
    final uid = _userId;
    if (uid == null) return;

    try {
      await sl<SupabaseClient>().from(_table).insert({
        'user_id': uid,
        'event_name': eventName,
        'properties': properties ?? {},
      });
      AppLogger.debug('Event tracked: $eventName', tag: _tag);
    } on Object catch (e) {
      AppLogger.warn('Failed to track event $eventName: $e', tag: _tag);
    }
  }

  Future<void> _insertOnce(
    String eventName,
    Map<String, dynamic>? properties,
  ) async {
    final uid = _userId;
    if (uid == null) return;

    try {
      final existing = await sl<SupabaseClient>()
          .from(_table)
          .select('id')
          .eq('user_id', uid)
          .eq('event_name', eventName)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        AppLogger.debug('Event $eventName already tracked, skipping',
            tag: _tag);
        return;
      }

      await sl<SupabaseClient>().from(_table).insert({
        'user_id': uid,
        'event_name': eventName,
        'properties': properties ?? {},
      });
      AppLogger.debug('Event tracked (once): $eventName', tag: _tag);
    } on Object catch (e) {
      AppLogger.warn('Failed to track event $eventName: $e', tag: _tag);
    }
  }

  String? get _userId {
    if (!AppConfig.isSupabaseReady) return null;
    try {
      return sl<SupabaseClient>().auth.currentUser?.id;
    } on Object catch (e) {
      AppLogger.warn('Caught error', tag: 'ProductEventTracker', error: e);
      return null;
    }
  }
}

/// Canonical event names for product tracking.
abstract final class ProductEvents {
  static const onboardingCompleted = 'onboarding_completed';
  static const firstChallengeCreated = 'first_challenge_created';
  static const firstChampionshipLaunched = 'first_championship_launched';
  static const flowAbandoned = 'flow_abandoned';
}
