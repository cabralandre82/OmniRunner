import 'prefs_safe_key.dart';

/// Centralized SharedPreferences key constants.
///
/// Use these instead of magic strings to ensure consistency and avoid typos.
///
/// ### L11-05 — SharedPreferences vs FlutterSecureStorage
///
/// **SharedPreferences is UNENCRYPTED plaintext on disk** (iOS: NSUserDefaults;
/// Android: SharedPreferences XML). Anyone with root / a backup decrypter can
/// read what you put here.
///
/// This catalogue is the SINGLE allowed entry point for the SharedPreferences
/// keyspace. Every entry runs through [PrefsSafeKey.assertSafe] at load time
/// (see the `static final` initialisers below), which rejects any key matching
/// secret-sounding words (token, secret, password, credential, api_key,
/// auth_token, jwt, bearer, oauth_state, refresh_token, access_token, pin,
/// cvv, cpf, ssn, passport, ...).
///
/// If your data is sensitive, use [FlutterSecureStorage] instead (see
/// `lib/features/strava/data/strava_secure_store.dart`,
/// `lib/core/secure_storage/db_secure_store.dart`,
/// `lib/features/strava/data/strava_oauth_state.dart` for examples).
///
/// CI guard: `npm run audit:shared-prefs-sensitive-keys`
/// Runbook:  docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md
/// Finding:  docs/audit/findings/L11-05-flutter-secure-storage-10-0-0-mas-release.md
class PreferencesKeys {
  PreferencesKeys._();

  // ─────────────────────────── Prefixes ─────────────────────────────────
  //
  // Prefix entries are PrefsSafeKey instances; callers concatenate the
  // suffix. We expose [.name] for backward-compat with existing string
  // concatenation sites (`'${PreferencesKeys.tipSeenPrefix}${key.name}'`).

  /// Prefix for cache metadata entries (append key and optionally _userId).
  static final PrefsSafeKey _cacheMetaPrefixKey = PrefsSafeKey.prefix(
    'cache_meta_',
    purpose: 'HTTP + repository cache metadata (expires_at, etag)',
  );

  /// Prefix for first-use tip keys (append TipKey.name).
  static final PrefsSafeKey _tipSeenPrefixKey = PrefsSafeKey.prefix(
    'tip_seen_',
    purpose: 'UI hint "have I seen this tooltip yet" flag',
  );

  /// Prefix for onboarding tooltip keys (append tooltipId).
  static final PrefsSafeKey _onboardingTooltipPrefixKey = PrefsSafeKey.prefix(
    'onboarding_tooltip_',
    purpose: 'UI onboarding walkthrough "seen" flag',
  );

  static String get cacheMetaPrefix => _cacheMetaPrefixKey.name;
  static String get tipSeenPrefix => _tipSeenPrefixKey.name;
  static String get onboardingTooltipPrefix => _onboardingTooltipPrefixKey.name;

  // ─────────────────────────── Single-key entries ───────────────────────

  static final PrefsSafeKey _themeMode = PrefsSafeKey.plain(
    'theme_mode',
    purpose: 'UI theme (system|light|dark)',
  );

  static final PrefsSafeKey _pendingInviteCode = PrefsSafeKey.plain(
    'pending_invite_code',
    purpose:
        'deep-link invite code (public code shareable by design, consumed once)',
  );

  static final PrefsSafeKey _offlineQueueItems = PrefsSafeKey.plain(
    'offline_queue_items',
    purpose: 'non-sensitive queued API payloads (no auth headers)',
  );

  static final PrefsSafeKey _offlineQueue = PrefsSafeKey.plain(
    'offline_queue',
    purpose: 'legacy offline queue (utils/offline_queue.dart)',
  );

  static final PrefsSafeKey _omniLocalUserId = PrefsSafeKey.plain(
    'omni_local_user_id',
    purpose: 'local-mock user uuid (dev-only persona)',
  );

  static final PrefsSafeKey _coachKmEnabled = PrefsSafeKey.plain(
    'coach_km_enabled',
    purpose: 'coach voice: km-split announcements on/off',
  );

  static final PrefsSafeKey _coachGhostEnabled = PrefsSafeKey.plain(
    'coach_ghost_enabled',
    purpose: 'coach voice: ghost-runner announcements on/off',
  );

  static final PrefsSafeKey _coachPeriodicEnabled = PrefsSafeKey.plain(
    'coach_periodic_enabled',
    purpose: 'coach voice: periodic summary on/off',
  );

  static final PrefsSafeKey _coachHrZoneEnabled = PrefsSafeKey.plain(
    'coach_hr_zone_enabled',
    purpose: 'coach voice: HR zone alerts on/off',
  );

  static final PrefsSafeKey _coachMaxHr = PrefsSafeKey.plain(
    'coach_max_hr',
    purpose: 'athlete-declared max HR (bpm)',
  );

  static final PrefsSafeKey _coachUseImperial = PrefsSafeKey.plain(
    'coach_use_imperial',
    purpose: 'unit system toggle (imperial vs metric)',
  );

  static final PrefsSafeKey _coachProfileVisibleRanking = PrefsSafeKey.plain(
    'coach_profile_visible_ranking',
    purpose: 'privacy: show profile in ranking lists',
  );

  static final PrefsSafeKey _coachShareActivityFeed = PrefsSafeKey.plain(
    'coach_share_activity_feed',
    purpose: 'privacy: share activities to group feed',
  );

  static final PrefsSafeKey _bleHrLastDeviceId = PrefsSafeKey.plain(
    'ble_hr_last_device_id',
    purpose: 'last-paired BLE heart-rate device id (public MAC / alias)',
  );

  static final PrefsSafeKey _bleHrLastDeviceName = PrefsSafeKey.plain(
    'ble_hr_last_device_name',
    purpose: 'last-paired BLE heart-rate device display name',
  );

  static final PrefsSafeKey _hasSeenGarminImportGuide = PrefsSafeKey.plain(
    'has_seen_garmin_import_guide',
    purpose: 'UI: Garmin/FIT import guide "seen" flag',
  );

  /// L21-06 — athlete-selected GPS recording mode
  /// (see [RecordingMode]). String value: "standard" (default) or
  /// "performance" (1 m filter + bestForNavigation, ~+30 % battery).
  /// Non-sensitive: just a UI toggle, not an identifier.
  static final PrefsSafeKey _recordingMode = PrefsSafeKey.plain(
    'recording_mode',
    purpose: 'L21-06: GPS recording mode (standard|performance)',
  );

  // ─────────────────────────── Public string facade ─────────────────────
  //
  // Call-sites use these as `prefs.getString(PreferencesKeys.themeMode)`.
  // The getter dereferences the PrefsSafeKey (which has already been
  // validated at class load). We expose `String` not `PrefsSafeKey` to
  // minimise churn at existing call-sites.

  static String get themeMode => _themeMode.name;
  static String get pendingInviteCode => _pendingInviteCode.name;
  static String get offlineQueueItems => _offlineQueueItems.name;
  static String get offlineQueue => _offlineQueue.name;
  static String get omniLocalUserId => _omniLocalUserId.name;
  static String get coachKmEnabled => _coachKmEnabled.name;
  static String get coachGhostEnabled => _coachGhostEnabled.name;
  static String get coachPeriodicEnabled => _coachPeriodicEnabled.name;
  static String get coachHrZoneEnabled => _coachHrZoneEnabled.name;
  static String get coachMaxHr => _coachMaxHr.name;
  static String get coachUseImperial => _coachUseImperial.name;
  static String get coachProfileVisibleRanking =>
      _coachProfileVisibleRanking.name;
  static String get coachShareActivityFeed => _coachShareActivityFeed.name;
  static String get bleHrLastDeviceId => _bleHrLastDeviceId.name;
  static String get bleHrLastDeviceName => _bleHrLastDeviceName.name;
  static String get hasSeenGarminImportGuide => _hasSeenGarminImportGuide.name;
  static String get recordingMode => _recordingMode.name;

  // ─────────────────────────── Catalogue introspection ──────────────────

  /// All PrefsSafeKey instances declared above. Used by tests to validate
  /// invariants and by diagnostics tools to enumerate the keyspace.
  ///
  /// Order matches declaration order, purely for readability.
  static final List<PrefsSafeKey> allKeys = <PrefsSafeKey>[
    _cacheMetaPrefixKey,
    _tipSeenPrefixKey,
    _onboardingTooltipPrefixKey,
    _themeMode,
    _pendingInviteCode,
    _offlineQueueItems,
    _offlineQueue,
    _omniLocalUserId,
    _coachKmEnabled,
    _coachGhostEnabled,
    _coachPeriodicEnabled,
    _coachHrZoneEnabled,
    _coachMaxHr,
    _coachUseImperial,
    _coachProfileVisibleRanking,
    _coachShareActivityFeed,
    _bleHrLastDeviceId,
    _bleHrLastDeviceName,
    _hasSeenGarminImportGuide,
    _recordingMode,
  ];
}
