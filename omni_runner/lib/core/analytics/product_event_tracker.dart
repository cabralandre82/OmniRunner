import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Lightweight, fire-and-forget product event tracker.
///
/// Writes to `product_events` table in Supabase. Events are append-only
/// and used for product analytics (onboarding funnel, first-use
/// milestones, flow abandonment). No PII beyond `user_id`.
///
/// Defence model (L08-01 + L08-02):
///
///   • The Postgres trigger `trg_validate_product_event` is the canonical
///     enforcement point — it rejects unknown event names, unknown
///     property keys, nested objects/arrays, and oversize string values
///     with SQLSTATE PE001..PE005. The constants below MIRROR that
///     trigger so we fail fast at the call site instead of round-tripping
///     to the DB.
///   • For the one-shot event family ([_isOneShot]), [trackOnce] issues
///     a plain `insert` and swallows the `unique_violation` (SQLSTATE
///     23505) raised by the partial index
///     `idx_product_events_user_event_once`. We can't use
///     `upsert(ignoreDuplicates: true)` here because PostgREST does
///     not allow attaching the partial-index predicate to the
///     `ON CONFLICT` clause; the unique-violation-and-swallow pattern
///     reaches the same end-state (single row per user/event) under
///     arbitrary concurrency (double-tap, retry-after-network-blip,
///     online-resync) without inflating the funnel.
///
/// When you need to add a new event/property, follow
/// `docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md` (4 places to update).
class ProductEventTracker {
  static const _tag = 'ProductEvents';
  static const _table = 'product_events';

  /// Track a product event (fire-and-forget).
  ///
  /// [eventName] — must be one of [ProductEvents.allowedNames].
  /// [properties] — optional flat key-value map. Keys must be in
  /// [ProductEvents.allowedPropertyKeys]; values must be primitives
  /// (String/num/bool/null) ≤ [ProductEvents.maxStringValueLength].
  ///
  /// Invalid input is dropped with a warning log instead of throwing —
  /// analytics must never block user flow. The Postgres trigger is the
  /// guarantee; this is just to surface drift early in dev.
  void track(String eventName, [Map<String, dynamic>? properties]) {
    _insert(eventName, properties, oneShot: false);
  }

  /// Track an event only if the user hasn't triggered it before.
  ///
  /// Used for one-time milestones like
  /// [ProductEvents.firstChallengeCreated] and
  /// [ProductEvents.onboardingCompleted]. Implemented as a plain
  /// `insert` that catches the `unique_violation` (SQLSTATE 23505)
  /// raised by the partial index `idx_product_events_user_event_once`.
  /// Concurrent calls with the same `(user_id, event_name)` collapse
  /// into a single row — no more select+insert TOCTOU race.
  void trackOnce(String eventName, [Map<String, dynamic>? properties]) {
    if (!ProductEvents._isOneShot(eventName)) {
      AppLogger.warn(
        'trackOnce called with non-one-shot event "$eventName" — '
        'falling back to track(). Add it to ProductEvents._oneShotPrefixes '
        'or use track().',
        tag: _tag,
      );
      _insert(eventName, properties, oneShot: false);
      return;
    }
    _insert(eventName, properties, oneShot: true);
  }

  Future<void> _insert(
    String eventName,
    Map<String, dynamic>? properties, {
    required bool oneShot,
  }) async {
    final uid = _userId;
    if (uid == null) return;

    final validation = ProductEvents.validate(eventName, properties);
    if (validation != null) {
      AppLogger.warn(
        'Dropping invalid product event "$eventName": $validation',
        tag: _tag,
      );
      return;
    }

    final payload = <String, dynamic>{
      'user_id': uid,
      'event_name': eventName,
      'properties': properties ?? <String, dynamic>{},
    };

    try {
      await sl<SupabaseClient>().from(_table).insert(payload);
      AppLogger.debug(
        oneShot ? 'Event tracked (once): $eventName' : 'Event tracked: $eventName',
        tag: _tag,
      );
    } on PostgrestException catch (e) {
      // L08-01: for one-shot events, the unique partial index
      // idx_product_events_user_event_once raises 23505 when the user
      // already has the event. That is the EXPECTED idempotent path
      // under concurrent calls — log at debug level and move on.
      if (oneShot && e.code == '23505') {
        AppLogger.debug(
          'One-shot event $eventName already recorded (idempotent skip)',
          tag: _tag,
        );
        return;
      }
      AppLogger.warn('Failed to track event $eventName: $e', tag: _tag);
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

/// Canonical event names + validation for product tracking.
///
/// Mirrors `fn_validate_product_event()` in the Postgres migration
/// `20260421100000_l08_product_events_hardening.sql`. Drift between
/// the two is caught by the integration test
/// `tools/test_l08_01_02_product_events_hardening.ts`.
abstract final class ProductEvents {
  // ── Event name constants (8 events). Keep alphabetical inside a group. ──

  static const billingCheckoutReturned = 'billing_checkout_returned';
  static const billingCreditsViewed = 'billing_credits_viewed';
  static const billingPurchasesViewed = 'billing_purchases_viewed';
  static const billingSettingsViewed = 'billing_settings_viewed';

  static const firstChallengeCreated = 'first_challenge_created';
  static const firstChampionshipLaunched = 'first_championship_launched';

  static const flowAbandoned = 'flow_abandoned';
  static const onboardingCompleted = 'onboarding_completed';

  /// Whitelist of allowed event names. Mirror of the Postgres trigger
  /// constant `v_allowed_events`.
  static const Set<String> allowedNames = <String>{
    billingCheckoutReturned,
    billingCreditsViewed,
    billingPurchasesViewed,
    billingSettingsViewed,
    firstChallengeCreated,
    firstChampionshipLaunched,
    flowAbandoned,
    onboardingCompleted,
  };

  /// Whitelist of allowed property keys. Mirror of the Postgres trigger
  /// constant `v_allowed_keys`. NEVER add free-text fields like
  /// `email`, `name`, `cpf`, `lat`, `lng`, `polyline`, `comment` etc.
  /// — those would re-introduce the L08-02 PII risk.
  static const Set<String> allowedPropertyKeys = <String>{
    'balance',
    'challenge_id',
    'championship_id',
    'count',
    'duration_ms',
    'flow',
    'goal',
    'group_id',
    'method',
    'metric',
    'outcome',
    'products_count',
    'reason',
    'role',
    'step',
    'template_id',
    'total_count',
    'type',
  };

  /// Maximum length of any string property value. Mirror of the
  /// Postgres trigger constant `v_max_string_len`.
  static const int maxStringValueLength = 200;

  /// Event names that the unique partial index protects under
  /// concurrent insert. Mirror of the predicate on
  /// `idx_product_events_user_event_once`.
  static bool _isOneShot(String eventName) {
    return eventName.startsWith('first_') ||
        eventName == onboardingCompleted;
  }

  /// Validate an event before insert. Returns `null` when valid, or a
  /// human-readable reason string when invalid. Defensive mirror of the
  /// Postgres trigger — same rules, same reject set, just enforced
  /// earlier in the pipeline so dev typos surface in the log
  /// immediately instead of round-tripping through Supabase.
  static String? validate(
    String eventName,
    Map<String, dynamic>? properties,
  ) {
    if (!allowedNames.contains(eventName)) {
      return 'unknown event_name (allowed: '
          '${(allowedNames.toList()..sort()).join(", ")})';
    }
    if (properties == null) return null;

    for (final entry in properties.entries) {
      final key = entry.key;
      final value = entry.value;

      if (!allowedPropertyKeys.contains(key)) {
        return 'unknown property key "$key" (PII risk — see '
            'PRODUCT_EVENTS_RUNBOOK)';
      }

      // Only primitives. Dart Maps and Iterables map to JSON
      // objects/arrays, which the Postgres trigger rejects with PE003.
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool) {
        return 'property "$key" has unsupported value type '
            '${value.runtimeType} — only String/num/bool/null allowed';
      }

      if (value is String && value.length > maxStringValueLength) {
        return 'property "$key" string value exceeds '
            '$maxStringValueLength chars (got ${value.length})';
      }
    }
    return null;
  }
}
