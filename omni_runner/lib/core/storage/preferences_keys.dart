/// Centralized SharedPreferences key constants.
///
/// Use these instead of magic strings to ensure consistency and avoid typos.
class PreferencesKeys {
  PreferencesKeys._();

  /// Prefix for cache metadata entries (append key and optionally _userId).
  static const cacheMetaPrefix = 'cache_meta_';

  /// Prefix for first-use tip keys (append TipKey.name).
  static const tipSeenPrefix = 'tip_seen_';

  /// Prefix for onboarding tooltip keys (append tooltipId).
  static const onboardingTooltipPrefix = 'onboarding_tooltip_';

  // Theme
  static const themeMode = 'theme_mode';

  // Deep links
  static const pendingInviteCode = 'pending_invite_code';

  // Offline
  static const offlineQueueItems = 'offline_queue_items';
  static const offlineQueue = 'offline_queue'; // legacy utils/offline_queue.dart

  // Auth (mock / local)
  static const omniLocalUserId = 'omni_local_user_id';

  // Coach settings
  static const coachKmEnabled = 'coach_km_enabled';
  static const coachGhostEnabled = 'coach_ghost_enabled';
  static const coachPeriodicEnabled = 'coach_periodic_enabled';
  static const coachHrZoneEnabled = 'coach_hr_zone_enabled';
  static const coachMaxHr = 'coach_max_hr';
  static const coachUseImperial = 'coach_use_imperial';
  static const coachProfileVisibleRanking = 'coach_profile_visible_ranking';
  static const coachShareActivityFeed = 'coach_share_activity_feed';

  // BLE heart rate
  static const bleHrLastDeviceId = 'ble_hr_last_device_id';
  static const bleHrLastDeviceName = 'ble_hr_last_device_name';

  // Export / integrations
  static const hasSeenGarminImportGuide = 'has_seen_garmin_import_guide';
}
