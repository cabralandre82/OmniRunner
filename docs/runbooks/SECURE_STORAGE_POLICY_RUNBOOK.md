# SECURE STORAGE POLICY RUNBOOK — L11-05

> **Audit refs:** L11-05 · [`docs/audit/findings/L11-05-flutter-secure-storage-10-0-0-mas-release.md`](../audit/findings/L11-05-flutter-secure-storage-10-0-0-mas-release.md) · anchor `[11.5]` in [`docs/audit/parts/05-cro-cso-supply-cron.md`](../audit/parts/05-cro-cso-supply-cron.md)
> **Status:** fixed (2026-04-21)
> **Owner:** mobile
> **Related:** L11-06 (dependency pinning), L11-07 (sqlcipher EOL), L01-29 (Strava OAuth CSRF state — consumer of `FlutterSecureStorage`), L01-30/31 (release hardening)

---

## 1. Why this exists

The Flutter app declares BOTH storage backends in `omni_runner/pubspec.yaml`:

```yaml
shared_preferences: ^2.5.4      # plaintext XML / NSUserDefaults
flutter_secure_storage: ^10.0.0 # Keychain / EncryptedSharedPreferences
```

Before this PR, nothing mechanically prevented a developer from casually reaching for `SharedPreferences` and storing a Strava access token, Supabase JWT, Apple sign-in identifier, or any other credential alongside the theme preference. A single PR slip would leak the secret into:

- **iOS:** `~/Library/Preferences/<bundle>.plist` — recoverable from any iTunes / Finder backup, readable by any jailbroken-device malware under the same bundle.
- **Android (< 11):** `/data/data/<package>/shared_prefs/*.xml` — world-readable if the device is rooted, extractable via `adb backup` on older OEM builds.
- **Android (≥ 11 TalkBack export):** some backup services still include SharedPreferences by default unless explicitly excluded in `<allowBackup/>` or `data_extraction_rules.xml`.

By contrast, `FlutterSecureStorage` binds to:

- **iOS:** Keychain with `kSecAttrAccessibleAfterFirstUnlock` (default) — locked at device-unlock level, wiped on passcode reset.
- **Android:** `EncryptedSharedPreferences` (Jetpack Security) on API 23+, falling back to the system Keystore primitives — keys never leave the hardware-backed TEE on supported devices.

L10-09 (anti-credential stuffing) lands a sign-in verification email flow that will churn short-lived codes through storage if we ever cache them client-side. L07-04 (Strava OAuth state CSRF) already stores the state nonce in `FlutterSecureStorage` — any regression that reroutes it through SharedPreferences silently converts an RFC 6749 §10.12 defence into a trivially-exploitable CSRF path. We need a **mechanical** fence, not documentation alone.

---

## 2. The policy

### 2.1 Use `FlutterSecureStorage` for

| Category | Examples |
|---|---|
| OAuth / OIDC tokens | Strava access/refresh tokens, Supabase JWT, Apple ID token |
| OAuth state / nonce | Strava CSRF state (already done — L01-29/L07-04) |
| Encryption keys | SQLCipher master key (already done — `db_secure_store.dart`) |
| Passwords | Master password, legacy local-account passwords |
| MFA / TOTP secrets | Backup codes, TOTP seed |
| Payment credentials | Card numbers (never store raw), CVV (never store at all) |
| Government IDs | CPF, SSN, passport numbers |
| Biometric salts | WebAuthn counters, device-bound salts |

### 2.2 Use `SharedPreferences` for

| Category | Examples |
|---|---|
| UI state | theme mode, "have you seen this tooltip", walkthrough progress |
| User preferences (non-sensitive) | unit system (imperial/metric), coach voice toggles, ranking opt-in |
| Public identifiers | last-paired BLE device MAC, public group ID |
| Caches (non-credentialed) | cache metadata (expires_at, ETag — but NEVER response bodies containing auth headers) |
| Queue placeholders | offline queue IDs (but NOT the payload if it contains auth material) |
| Invite codes | invite codes are by design shareable and consumed once |

### 2.3 Use NEITHER (always transient)

- Raw CVV, card-verification values → never persisted, sent straight to the payment provider.
- One-time-use challenge nonces → in-memory only, discarded after consumption.
- Biometric proof blobs from WebAuthn → forwarded to server, never cached.

---

## 3. Enforcement — three layers of defence

### 3.1 Layer 1 — `PreferencesKeys` catalogue (compile + boot time)

`omni_runner/lib/core/storage/preferences_keys.dart` is the ONLY place the codebase is allowed to declare a SharedPreferences key name. Every entry goes through `PrefsSafeKey.plain(...)` or `PrefsSafeKey.prefix(...)`, which run `assertSafe(name)` at constructor time. Any future PR that adds a key like `'access_token'` to the catalogue will crash app-boot with `PrefsSafeKeyViolation` — the runtime guard is **not** opt-out-able from within Dart.

If the reviewer genuinely believes a new key is safe despite matching the heuristic (e.g., `session_duration_ms` — which does NOT match because of the word-boundary rules, but hypothetically a future case might), they have two choices:

1. **Rename the key** so it does not match. This is always the preferred answer.
2. **Add the exact key name** to `PrefsSafeKey._explicitAllowlist` with a comment justifying why it is safe.

### 3.2 Layer 2 — CI guard `npm run audit:shared-prefs-sensitive-keys`

`tools/audit/check-shared-prefs-sensitive-keys.ts` scans every `.dart` file under `omni_runner/lib/**` and `omni_runner/test/**` (minus the guard files themselves). It flags:

- String-literal keys passed to `prefs.getX / setX / remove`.
- `PreferencesKeys.<name>` references (camelCase → snake_case normalised).
- Bare variable / getter names used as keys (a variable called `accessToken` triggers the guard even if its runtime value is not a literal).

Receivers recognised: `prefs`, `sharedPrefs`, `_prefs`, `p`, `sp`, `_pref`, `sharedPreferences`.

**Opt-out:** Append `// L11-05-OK: <reason>` on the offending line or the line immediately above. The CI guard surfaces every opt-out in its report so reviewers can audit them. Use this for rare legitimate false positives (e.g., an upstream SDK reserved key name we cannot rename).

### 3.3 Layer 3 — Dart test `preferences_keys_test.dart`

`omni_runner/test/core/storage/preferences_keys_test.dart` runs as part of `flutter test` and asserts:

1. Every key in `PreferencesKeys.allKeys` passes `assertSafe`.
2. Representative sensitive words (`access_token`, `api_key`, `oauth_state`, `cpf`, ...) DO trigger `PrefsSafeKeyViolation`.
3. Representative safe keys (`theme_mode`, `coach_km_enabled`, `pending_invite_code`, ...) do NOT.
4. `strava_athlete_name` / `strava_athlete_id` pass despite sounding credential-ish (allowlist).
5. No duplicate keys in the catalogue.
6. Every entry has a non-empty `purpose` docstring > 8 chars (reviewers cannot judge sensitivity without a real description).
7. Prefix entries end in `_`.

---

## 4. How to add a new SharedPreferences key

1. **Pick a name that does NOT match the heuristic.** Run `PrefsSafeKey.assertSafe('<your_name>')` mentally or in a scratch Dart file.
2. **Add an entry to `PreferencesKeys`.** Use `PrefsSafeKey.plain('<name>', purpose: '<8+ char description of why this is non-sensitive>')`.
3. **Expose a String getter.** Follow the existing pattern — `static String get <camelName> => <backingKey>.name;`
4. **Add the instance to `PreferencesKeys.allKeys`.** Order matches declaration.
5. **Run `flutter test test/core/storage/preferences_keys_test.dart`.** The "every entry passes assertSafe" + "every entry has a non-empty purpose" + "no duplicate key names" tests enforce the contract.
6. **Run `npm run audit:shared-prefs-sensitive-keys`.** Confirm no violation.

**Don't** add a key that stores data derived from an auth flow. Examples of mistakes to avoid:

- Storing the Supabase user ID under `'user_session_id'` — matches `session_id`. Use a non-matching name (`current_user_uuid`) AND put it in SharedPreferences only if it's not a secret. User UUIDs are not secrets on their own, but `session_id` in many auth systems IS.
- Storing "last successful login timestamp" under `'last_login_token_refresh_at'` — matches `token`. Rename to `last_login_at_ms`.
- Storing feature-flag override values under `'override_api_key_disabled'` — matches `api_key`. Rename to `flag_inline_api_override_disabled`.

---

## 5. How to add a new secure-storage-backed component

Mirror the existing pattern in `lib/features/strava/data/strava_secure_store.dart`:

```dart
class MyFeatureSecureStore {
  final FlutterSecureStorage _storage;

  static const _keySomething = 'myfeature_something';

  const MyFeatureSecureStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  Future<String?> get something => _storage.read(key: _keySomething);
  Future<void> saveSomething(String v) => _storage.write(key: _keySomething, value: v);
  Future<void> clear() => _storage.delete(key: _keySomething);
}
```

Key conventions:
- Always prefix keys with your feature name (`myfeature_...`) to avoid cross-feature collisions in the global Keychain / EncryptedPrefs namespace.
- Inject `FlutterSecureStorage` so tests can substitute an in-memory adapter (see `test/features/strava/strava_oauth_state_test.dart` for the pattern).
- Expose getters and setters, never the raw `_storage` instance.
- Add a `clear()` method and call it on logout / disconnect. Stale tokens left in the Keychain after a user switches accounts are a well-trodden pre-production leak path.
- **Do not** declare the keys anywhere under `lib/core/storage/preferences_keys.dart` — that catalogue is SharedPreferences-only by construction. Secure-store keys live next to the consumer.

---

## 6. Operational playbooks

### 6.1 Discovered a leak — secret in SharedPreferences

**Signal:** Reviewer notices a line like `prefs.setString('strava_access_token', token)` during triage, or a Sentry breadcrumb contains a plaintext SharedPreferences dump.

**Actions:**
1. **Stop the leak:** patch the call-site to use `FlutterSecureStorage` instead. Migrate the in-memory value (if a live session exists) into secure storage atomically.
2. **Ship a migration block** on next app start that:
   ```dart
   final prefs = await SharedPreferences.getInstance();
   final stray = prefs.getString('strava_access_token');
   if (stray != null) {
     await secureStore.saveAccessToken(stray);
     await prefs.remove('strava_access_token');
   }
   ```
3. **Force refresh tokens** server-side for any user who had the leaky version installed (best-effort — scan Sentry / logs for affected user IDs; if not feasible, push a forced-relogin banner).
4. **Rotate any symmetric keys** derived from the leaked secret. Strava access tokens are short-lived (6h) so natural rotation handles the exposure window; Supabase JWT rotation needs a forced session refresh.
5. **Post-mortem:** document the gap, add a regex to `_sensitivePatterns` if the leaked keyword wasn't already covered, push a follow-up PR with the new pattern + matching test.

### 6.2 CI guard failed — unknown violation in `npm run audit:shared-prefs-sensitive-keys`

Three flavours:

- **Literal key in code:** rename the key, move to secure storage, or (rare) add `// L11-05-OK: <reason>` with a reviewer sign-off comment.
- **`PreferencesKeys.xxx` where `xxx` is new:** your new catalogue entry matches the heuristic. Rename it.
- **Bare variable name:** your variable is named suspiciously. Either rename the variable or, if the runtime value IS the suspicious thing, move to secure storage.

### 6.3 Dart test failed — `every entry passes assertSafe`

Someone added a new entry to `PreferencesKeys.allKeys` that the heuristic flags. Test output prints the offending name and the matched pattern; rename or (rare) allowlist.

### 6.4 `PrefsSafeKeyViolation` at app boot

A key made it into the catalogue somehow (bypassed tests, local build). The constructor throws immediately. Fix: find the offending `PrefsSafeKey.plain` / `.prefix` call and rename. The error message includes the matched keyword and the file offending line (Dart stack traces pinpoint the `preferences_keys.dart` line).

### 6.5 False positive — legitimate key flagged

Options, in decreasing order of preference:

1. **Rename.** Almost always possible.
2. **Add to `_explicitAllowlist`** in `prefs_safe_key.dart` with a comment explaining why the key is safe despite matching the heuristic. Both the runtime and the CI guard honour the allowlist.
3. **Refine the pattern.** If the heuristic is over-broad (e.g., matches `token` inside `tokenize`), tighten the regex in both `prefs_safe_key.dart::_sensitivePatterns` AND `tools/audit/check-shared-prefs-sensitive-keys.ts::SENSITIVE_PATTERNS`. The two MUST stay in lockstep — CI parity is enforced by the guard's `ensureCatalogueBindingIntact()` which checks that `preferences_keys.dart` still imports `prefs_safe_key.dart`.

### 6.6 Audit dependency bumps

When `flutter_secure_storage` or `shared_preferences` ship a breaking change:

- `flutter_secure_storage`: read the CHANGELOG for platform-level changes. iOS Keychain access-group changes can invalidate existing tokens. Ship a "re-login" migration if needed.
- `shared_preferences`: platform changes here are rare but do happen (Android 14 bumped from SharedPreferences XML to DataStore for new installations in some OEM forks). Our guard is insensitive to the backing store — it only cares about key naming.

---

## 7. Detection signals

| Signal | Source | Action |
|---|---|---|
| CI red on `npm run audit:shared-prefs-sensitive-keys` | GitHub Actions | §6.2 |
| Flutter test red on `preferences_keys_test.dart` | `flutter test` | §6.3 |
| App boot crash with `PrefsSafeKeyViolation` | Sentry crash-free% dashboard | §6.4 |
| New `.dart` file with `SharedPreferences.getInstance()` not wrapping through repository | PR review | require the PR use `PreferencesKeys.*` not raw literals |
| New `pub get` resolves a `flutter_secure_storage` or `shared_preferences` major bump | `flutter pub outdated` | audit release notes, ship migration if needed |

---

## 8. Cross-refs

- **L01-29 / L07-04** — Strava OAuth state nonce lives in `FlutterSecureStorage` via `strava_oauth_state.dart`. Any regression that reroutes it to SharedPreferences turns the CSRF defence into a trivially-exploitable vector.
- **L04-07** — `coin_ledger.reason` PII protection; this is the server-side analogue of the mobile policy. The client-side fence here prevents the mobile app from ever putting PII where the server's redaction doesn't reach.
- **L11-06 / L11-07 / L11-08** — dependency pinning / SQLCipher EOL / Flutter SDK pinning, also in the Supply-Chain lens. This runbook's `pub get` guidance assumes those are in place.
- **L10-09** — anti-credential-stuffing ships sign-in verification emails that MUST NOT cache verification codes client-side. If future work adds a "remember this verification code" feature for UX reasons, the value goes into `FlutterSecureStorage`, never SharedPreferences.
- **L01-30 / L01-31** — Android release hardening (R8/ProGuard + signing fail-loud). Keys bleeding through obfuscation boundaries is a complementary concern; this runbook does NOT replace that hardening.
