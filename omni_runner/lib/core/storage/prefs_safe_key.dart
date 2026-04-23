// ---------------------------------------------------------------------------
// L11-05 — SharedPreferences key safety layer
// ---------------------------------------------------------------------------
//
// Problem this file solves:
//   pubspec.yaml declares BOTH `shared_preferences` (plaintext, unencrypted
//   UserDefaults / XML) and `flutter_secure_storage` (Keychain / EncryptedPrefs).
//   Nothing in the codebase mechanically prevented a future dev from storing a
//   Strava access_token, Supabase JWT, Apple sign-in user identifier, or any
//   other secret in the plaintext store just because SharedPreferences is
//   "easier".
//
// Defence posture:
//   This module refuses — at construction time — any key that looks like it
//   names a secret. Callers MUST route through [PrefsSafeKey] or through the
//   centralised [PreferencesKeys] catalogue (which itself constructs
//   `PrefsSafeKey` instances internally).
//
//   Violations throw [PrefsSafeKeyViolation] (an ArgumentError subclass) at
//   app-boot time in debug AND release. We WANT this to crash loudly — a
//   secret key slipping into plaintext is a data-loss class bug, not a "log
//   and continue" warning.
//
// What is considered "sensitive"?
//   Case-insensitive regex over the key string:
//     token | secret | password | credential | api[_-]?key | auth[_-]?token
//     | private[_-]?key | refresh[_-]?token | access[_-]?token | jwt
//     | bearer | session[_-]?id | oauth[_-]?state | mfa[_-]?code | otp
//     | pin[_-]?code | cvv | card[_-]?number | ssn | cpf | passport
//     | strava(?!_athlete_)          // strava_athlete_name/id are public metadata
//
// Opt-out:
//   There is NO opt-out at this layer. If a caller legitimately needs a key
//   that collides (e.g., `session_duration_ms` — contains the substring
//   `session`), the regex above is tuned to NOT match bare `session` — only
//   `session_id` / `session_token`. Add new words to the allowlist [kAllowed]
//   with a justification comment.
//
// Cross-refs:
//   - Companion CI guard: `tools/audit/check-shared-prefs-sensitive-keys.ts`
//     (`npm run audit:shared-prefs-sensitive-keys`).
//   - Runbook: docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md.
//   - Finding: docs/audit/findings/L11-05-flutter-secure-storage-10-0-0-mas-release.md
//   - Secure storage users: lib/features/strava/data/strava_secure_store.dart,
//     lib/core/secure_storage/db_secure_store.dart,
//     lib/features/strava/data/strava_oauth_state.dart.
// ---------------------------------------------------------------------------

/// Thrown when a caller tries to construct a [PrefsSafeKey] with a name that
/// our heuristic flags as sensitive.
///
/// Treat this as a data-loss-class bug: a secret was about to land in the
/// unencrypted plaintext store. Fix the call-site to use
/// [FlutterSecureStorage] instead.
class PrefsSafeKeyViolation extends ArgumentError {
  PrefsSafeKeyViolation(String keyName, String matchedPattern)
      : super.value(
          keyName,
          'PreferencesKey',
          'L11-05: SharedPreferences key "$keyName" matches sensitive '
              'pattern "$matchedPattern". Use FlutterSecureStorage instead '
              '(see docs/runbooks/SECURE_STORAGE_POLICY_RUNBOOK.md).',
        );
}

/// Compile- & boot-time checked SharedPreferences key.
///
/// Construct via [PrefsSafeKey.plain] for direct keys or
/// [PrefsSafeKey.prefix] for prefix templates (e.g. `cache_meta_<suffix>`).
/// Every construction runs [assertSafe] — if the heuristic matches, we throw
/// [PrefsSafeKeyViolation] immediately, which is always caught at app boot
/// (we construct every canonical key in [PreferencesKeys]'s static
/// initialisers).
class PrefsSafeKey {
  /// The raw key name stored in SharedPreferences.
  final String name;

  /// Short human-readable purpose, surfaced in logs + runbooks.
  final String purpose;

  /// Whether this key is a prefix-template (appended to by call-sites) vs. a
  /// complete key. Prefix templates are validated conservatively — suffixes
  /// are NOT re-validated at append time, so the prefix ITSELF must be clean.
  final bool isPrefix;

  PrefsSafeKey._(this.name, this.purpose, this.isPrefix);

  /// Canonical constructor for a complete SharedPreferences key.
  ///
  /// Throws [PrefsSafeKeyViolation] if [name] matches the sensitive regex.
  factory PrefsSafeKey.plain(String name, {required String purpose}) {
    assertSafe(name);
    return PrefsSafeKey._(name, purpose, false);
  }

  /// Prefix-template constructor (e.g., `cache_meta_` + `<user_id>`).
  ///
  /// Still subject to [assertSafe] — we do NOT allow smuggling sensitive
  /// keywords into the prefix even if the suffix is "benign".
  factory PrefsSafeKey.prefix(String prefix, {required String purpose}) {
    assertSafe(prefix);
    return PrefsSafeKey._(prefix, purpose, true);
  }

  @override
  String toString() => name;

  // ─────────────────────────── heuristic ────────────────────────────────

  /// Words / phrases that, when matched case-insensitively against a key,
  /// force the key into the secure-storage tier.
  ///
  /// Each entry is a raw regex fragment; they are joined with `|` at call
  /// time. Order does not matter — the first match wins and its pattern is
  /// surfaced in the error message for faster triage.
  ///
  /// **Word boundaries**: Dart regex `\b` treats `_` as a word character,
  /// so `\btoken\b` would NOT match `access_token`. Instead we use explicit
  /// lookaround `(?<![a-zA-Z])` / `(?![a-zA-Z])` so the pattern matches
  /// across underscore-separated tokens (`strava_access_token`,
  /// `api-key`, etc.) while still rejecting innocent substrings bordered
  /// by letters (`tokenize` → does NOT match `token`).
  ///
  /// If you need to add a word here, drop a cross-ref comment to the call
  /// that discovered the gap.
  static const String _lb = r'(?<![a-zA-Z])';
  static const String _rb = r'(?![a-zA-Z])';
  static final List<String> _sensitivePatterns = <String>[
    '${_lb}tokens?$_rb',
    '${_lb}secret$_rb',
    '${_lb}password$_rb',
    '${_lb}credential$_rb',
    '${_lb}api[_-]?key$_rb',
    '${_lb}auth[_-]?(?:token|secret|code)$_rb',
    '${_lb}private[_-]?key$_rb',
    '${_lb}refresh[_-]?token$_rb',
    '${_lb}access[_-]?token$_rb',
    '${_lb}jwt$_rb',
    '${_lb}bearer$_rb',
    '${_lb}session[_-]?(?:id|token|secret)$_rb',
    '${_lb}oauth[_-]?(?:state|token|secret)$_rb',
    '${_lb}mfa[_-]?(?:code|secret)$_rb',
    '${_lb}otp[_-]?(?:code|secret)?$_rb',
    '${_lb}pin[_-]?(?:code|hash)$_rb',
    '${_lb}cvv$_rb',
    '${_lb}card[_-]?number$_rb',
    '${_lb}ssn$_rb',
    '${_lb}cpf$_rb',
    '${_lb}passport$_rb',
    '${_lb}totp[_-]?secret$_rb',
  ];

  /// Compiled once per process. Null until first use, then memoised.
  static RegExp? _compiled;
  static RegExp get _regex =>
      _compiled ??= RegExp('(${_sensitivePatterns.join('|')})', caseSensitive: false);

  /// Words that sound sensitive but are not — documented with the reason.
  ///
  /// Example: `strava_athlete_name` is public profile metadata the user
  /// themselves expose on strava.com/athletes/<id>. We only blocklist
  /// `strava_access_token` etc.
  ///
  /// Entries here are checked BEFORE the sensitive regex.
  static const Set<String> _explicitAllowlist = <String>{
    'strava_athlete_name', // public Strava profile metadata
    'strava_athlete_id', // public Strava profile metadata
  };

  /// Throws [PrefsSafeKeyViolation] if [keyName] looks sensitive.
  ///
  /// Exposed for two reasons:
  ///   1. Tests can call it directly without constructing a [PrefsSafeKey].
  ///   2. Other code paths that happen to take an externally-supplied
  ///      key (e.g., a future dynamic feature-flag loader) can opt-in to
  ///      the same guard without refactoring.
  static void assertSafe(String keyName) {
    if (_explicitAllowlist.contains(keyName)) return;
    final m = _regex.firstMatch(keyName);
    if (m != null) {
      throw PrefsSafeKeyViolation(keyName, m.group(0) ?? '<unknown>');
    }
  }

  /// Returns true iff the given key name passes the sensitivity heuristic.
  ///
  /// Convenience for non-throwing contexts (lint output, UI diagnostics).
  /// The `on Error`-style catch is the entire contract of `isSafe`: turn
  /// the throwing heuristic into a boolean for callers that do not want
  /// to open a try/catch at their level.
  static bool isSafe(String keyName) {
    try {
      assertSafe(keyName);
      return true;
    } on PrefsSafeKeyViolation { // ignore: avoid_catching_errors
      return false;
    }
  }
}
