// L11-05 — SharedPreferences key safety invariants.
//
// Verifies:
//   1. Every canonical key in [PreferencesKeys] passes [PrefsSafeKey.assertSafe].
//   2. The heuristic flags representative sensitive keywords.
//   3. [PrefsSafeKey.isSafe] is a reliable boolean mirror of assertSafe.
//   4. No name collisions between keys (same prefix + different purpose).
//
// Runs as part of `flutter test` for the omni_runner mobile app.
//
// Companion guards:
//   - CI: `npm run audit:shared-prefs-sensitive-keys` (grep-based)
//   - Runbook: docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/storage/prefs_safe_key.dart';
import 'package:omni_runner/core/storage/preferences_keys.dart';

void main() {
  group('L11-05 — PrefsSafeKey heuristic', () {
    test('rejects sensitive keywords', () {
      final sensitive = <String>[
        'access_token',
        'refresh_token',
        'strava_access_token',
        'strava_refresh_token',
        'supabase_jwt',
        'apple_bearer_token',
        'api_key',
        'api-key',
        'apiKey',
        'user_password',
        'secret_encryption_key',
        'private_key',
        'mfa_secret',
        'totp_secret',
        'otp_code',
        'pin_code',
        'cvv',
        'card_number',
        'ssn',
        'user_cpf',
        'passport_id',
        'session_token',
        'session_id',
        'oauth_state',
        'auth_token',
        'auth_code',
        'credential_bundle',
      ];
      for (final s in sensitive) {
        expect(
          () => PrefsSafeKey.assertSafe(s),
          throwsA(isA<PrefsSafeKeyViolation>()),
          reason: 'expected "$s" to be flagged as sensitive',
        );
        expect(PrefsSafeKey.isSafe(s), isFalse);
      }
    });

    test('accepts non-sensitive keys', () {
      final safe = <String>[
        'theme_mode',
        'pending_invite_code',
        'offline_queue',
        'offline_queue_items',
        'omni_local_user_id',
        'coach_km_enabled',
        'coach_ghost_enabled',
        'coach_periodic_enabled',
        'coach_hr_zone_enabled',
        'coach_max_hr',
        'coach_use_imperial',
        'coach_profile_visible_ranking',
        'coach_share_activity_feed',
        'ble_hr_last_device_id',
        'ble_hr_last_device_name',
        'has_seen_garmin_import_guide',
        'cache_meta_',
        'tip_seen_',
        'onboarding_tooltip_',
        'cache_meta_session_list', // session_list is a data resource, not a credential
        'last_sync_at',
        'selected_group_id',
      ];
      for (final s in safe) {
        expect(
          () => PrefsSafeKey.assertSafe(s),
          returnsNormally,
          reason: '"$s" should pass the heuristic',
        );
        expect(PrefsSafeKey.isSafe(s), isTrue);
      }
    });

    test('explicit allowlist honors strava_athlete_name/id', () {
      // These LOOK like they'd match "strava" + metadata, but they are
      // PUBLIC profile fields (strava.com/athletes/<id>). The allowlist
      // pre-empts the regex.
      expect(PrefsSafeKey.isSafe('strava_athlete_name'), isTrue);
      expect(PrefsSafeKey.isSafe('strava_athlete_id'), isTrue);
    });

    test('error message surfaces the matched pattern for triage', () {
      try {
        PrefsSafeKey.assertSafe('my_access_token');
        fail('expected PrefsSafeKeyViolation');
      } on PrefsSafeKeyViolation catch (e) { // ignore: avoid_catching_errors
        expect(
          e.toString(),
          contains('L11-05'),
          reason: 'error carries the finding id',
        );
        expect(
          e.toString(),
          contains('FlutterSecureStorage'),
          reason: 'error points caller at the correct alternative',
        );
      }
    });
  });

  group('L11-05 — PreferencesKeys catalogue invariants', () {
    test('every entry passes assertSafe', () {
      for (final k in PreferencesKeys.allKeys) {
        expect(
          () => PrefsSafeKey.assertSafe(k.name),
          returnsNormally,
          reason: 'catalogue entry "${k.name}" (purpose: ${k.purpose}) '
              'must pass the secure-key heuristic',
        );
      }
    });

    test('no duplicate key names in the catalogue', () {
      final seen = <String>{};
      final dupes = <String>[];
      for (final k in PreferencesKeys.allKeys) {
        if (!seen.add(k.name)) dupes.add(k.name);
      }
      expect(dupes, isEmpty, reason: 'duplicate keys: $dupes');
    });

    test('every entry has a non-empty purpose docstring', () {
      for (final k in PreferencesKeys.allKeys) {
        expect(
          k.purpose.trim(),
          isNotEmpty,
          reason: 'catalogue entry "${k.name}" has empty purpose — '
              'describe why this lives in plaintext storage',
        );
        expect(
          k.purpose.length,
          greaterThan(8),
          reason: 'purpose for "${k.name}" is suspiciously short '
              '("${k.purpose}") — reviewers cannot judge sensitivity without '
              'a real description',
        );
      }
    });

    test('prefix entries end in underscore', () {
      for (final k in PreferencesKeys.allKeys) {
        if (k.isPrefix) {
          expect(
            k.name.endsWith('_'),
            isTrue,
            reason: 'prefix "${k.name}" should end in "_" to avoid '
                'accidental collision with non-prefix keys of the same '
                'literal stem',
          );
        }
      }
    });

    test('catalogue includes prefix entries as well as plain entries', () {
      final prefixCount = PreferencesKeys.allKeys.where((k) => k.isPrefix).length;
      final plainCount = PreferencesKeys.allKeys.where((k) => !k.isPrefix).length;
      expect(prefixCount, greaterThanOrEqualTo(1));
      expect(plainCount, greaterThanOrEqualTo(1));
    });
  });
}
