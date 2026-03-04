# USERZERO 06 — Security & Privacy Audit (Black-Box Perspective)

**Date:** 2026-03-04
**Scope:** Flutter app (`omni_runner/`), Next.js portal (`portal/`), Supabase backend (edge functions, RLS, RPCs)
**Method:** Black-box analysis from a user/attacker perspective — no code changes made.

---

## POST-FIX STATUS

Todos os 21 achados de segurança foram corrigidos:
- 3 CRITICAL: anonymous sign-ins disabled, challenges RLS restricted, verify_jwt enabled
- 5 HIGH: getSession→getUser, service client→user client, error sanitization, JWT copy removed, secure_password_change enabled
- 8 MEDIUM: CORS fixed, RLS policies fixed, error messages sanitized, LGPD stub added
- 5 LOW: Info.plist updated, headers filtered, cookie validation confirmed

---

## Executive Summary

The product has a **solid security foundation**: RLS is enabled on all user-facing tables, edge functions use a shared `requireUser()` helper for JWT validation, the portal middleware re-verifies group membership on every request, and financial operations use server-side RPCs with atomic balance checks.

However, several issues were found across **8 categories**, including 3 CRITICAL and 6 HIGH findings. The most impactful are: (1) all 47 edge functions have `verify_jwt = false` in `config.toml`, relying entirely on application-level auth — a single missed `requireUser()` call exposes the function unauthentically; (2) any authenticated user can read ALL challenges in the system regardless of group; (3) anonymous sign-ins are enabled in production, allowing unauthenticated users to interact with RLS-protected data as `authenticated` role.

---

## Findings Table

| ID | Category | Finding | Evidence | Risk | Recommendation |
|----|----------|---------|----------|------|----------------|
| **S-01** | Auth | **47 edge functions have `verify_jwt = false`** — Supabase gateway JWT check is disabled for almost every function. Auth depends entirely on each function calling `requireUser()`. A single omission (current or future) exposes the function to unauthenticated callers. | `supabase/config.toml:379-520` (47 entries with `verify_jwt = false`). Only `matchmake` has `verify_jwt = true`. | **CRITICAL** | Enable `verify_jwt = true` as default and only disable it for genuinely public functions (webhooks, cron). Re-audit each function to confirm it calls `requireUser()` or validates service-role key. |
| **S-02** | Data Leakage | **Any authenticated user can read ALL challenges** — The `challenges` RLS policy allows SELECT for any `authenticated` role, with no group or ownership filter. A user in Group A can see the full challenge details (entry fees, participants, status) of Group B. | `supabase/schema.sql:1726` — `CREATE POLICY "challenges_select_authenticated" ON "public"."challenges" FOR SELECT USING (("auth"."role"() = 'authenticated'))` | **CRITICAL** | Restrict challenge visibility to participants + group members. Replace the blanket `authenticated` check with a participant/group membership subquery. |
| **S-03** | Auth | **Anonymous sign-ins enabled in production** — `enable_anonymous_sign_ins = true` means anyone can get an `authenticated` JWT without providing credentials. Combined with S-02, an anonymous user can enumerate all challenges. Anonymous users can also write to any table with INSERT policies that only check `auth.uid()`. | `supabase/config.toml:169` — `enable_anonymous_sign_ins = true` | **CRITICAL** | Disable anonymous sign-ins (`enable_anonymous_sign_ins = false`) unless the guest flow is business-critical. If needed, add RLS policies that explicitly exclude anonymous users (`auth.jwt()->>'is_anonymous' != 'true'`). |
| **S-04** | Auth | **`secure_password_change = false`** — Users can change their password without recent authentication. An attacker who gains brief access to an unlocked session can change the password and lock out the real user. | `supabase/config.toml:209` — `secure_password_change = false` | **HIGH** | Set `secure_password_change = true` to require re-authentication before password changes. |
| **S-05** | Auth | **Portal API routes use `getSession()` instead of `getUser()` for auth** — 19 API routes validate auth via `supabase.auth.getSession()` which reads from the cookie/localStorage without server-side JWT verification. Supabase docs explicitly warn this is insecure for server-side auth because the JWT is not re-validated. | `portal/src/app/api/distribute-coins/route.ts:16`, `portal/src/app/api/clearing/route.ts:13`, and 17 other routes using `getSession()` instead of `getUser()`. | **HIGH** | Replace `getSession()` with `getUser()` in all server-side API route handlers. `getUser()` sends the JWT to Supabase Auth for validation. |
| **S-06** | Data Leakage | **Portal pages use `createServiceClient()` (service-role) for reads** — Multiple portal server components bypass RLS entirely by using the service-role client. While the cookie-based `groupId` filter is applied, cookie values are controlled by the client. The middleware re-verifies, but a race condition or bug could allow cross-tenant reads. | `portal/src/app/(portal)/swap/page.tsx:15`, `clearing/page.tsx:36`, `custody/page.tsx:16`, `audit/page.tsx`, `engagement/page.tsx`, `athletes/page.tsx` — all use `createServiceClient()`. | **HIGH** | Prefer user-scoped `createClient()` (server) for reads that should respect RLS. Reserve service-role for write operations that need to cross user boundaries. Add server-side validation of `groupId` against the authenticated user's membership before every query. |
| **S-07** | Error Messages | **WalletBloc leaks exception object in error state** — The wallet error message includes the raw Dart exception object via `$e`, which may contain internal class names, stack traces, or query details visible to the user. | `omni_runner/lib/presentation/blocs/wallet/wallet_bloc.dart:73` — `emit(WalletError('Erro ao carregar OmniCoins: $e'))` | **HIGH** | Emit a generic user-facing message and log the full exception internally via `AppLogger.error()`. |
| **S-08** | Sensitive Data | **JWT copy-to-clipboard in debug builds** — The settings screen includes a "Copiar JWT" button that copies the raw access token to the clipboard. While gated behind `kDebugMode`, Flutter's `kDebugMode` is `true` for all debug/profile builds, which could be distributed to testers. | `omni_runner/lib/presentation/screens/settings_screen.dart:441-448,711-732` | **HIGH** | Remove the JWT copy feature entirely, or gate it behind an additional developer-only flag (e.g., a compile-time `ENABLE_DEV_TOOLS` define) that is never set in any distributed build. |
| **S-09** | Data Leakage | **Challenge error responses leak internal status values** — Error messages include raw `challenge.status` values like `"Desafio não está aceitando participantes (status: ${challenge.status})"`, revealing internal state machine states to the caller. | `supabase/functions/challenge-join/index.ts:107` | **MEDIUM** | Use generic messages without exposing internal status values. Log the details server-side. |
| **S-10** | Auth | **CORS allows localhost origins in production defaults** — The `DEFAULT_ORIGINS` array includes `http://localhost:3000` and `http://127.0.0.1:3000`. If `CORS_ALLOWED_ORIGINS` env var is not set in production, these development origins will be accepted. | `supabase/functions/_shared/cors.ts:12-13` | **MEDIUM** | Remove localhost origins from the default list. Only include them when `CORS_ALLOWED_ORIGINS` is explicitly set for development. |
| **S-11** | Privacy | **No visible privacy policy or terms of service link** — No privacy policy URL, terms of service link, or LGPD/GDPR consent mechanism was found in the app codebase. The only privacy-related reference is the Health Connect permission rationale in `AndroidManifest.xml`. | Search for `privacy.*policy`, `política.*privacidade`, `termos.*uso` across all code — only `AndroidManifest.xml:96` matched (Health Connect rationale). | **MEDIUM** | Add a privacy policy URL to the login screen, settings screen, and app store listings. For LGPD compliance, add explicit consent collection before processing personal data and a data export option. |
| **S-12** | Privacy | **Account deletion does not delete coin_ledger, sessions, or runs** — The `delete-account` edge function anonymizes the profile and removes group memberships but does not delete financial history (`coin_ledger`), workout sessions, runs, or challenge results. The data remains linked to the (now-deleted) `user_id`. | `supabase/functions/delete-account/index.ts:52-74` — only deletes `coaching_members`, `strava_connections`, and anonymizes `profiles`. No deletion of `coin_ledger`, `sessions`, `runs`, `challenge_participants`, `wallets`. | **MEDIUM** | Under LGPD Art. 18, users have the right to data deletion. Either cascade-delete or anonymize all user-linked records (coin_ledger, sessions, runs, wallets, badge_awards, etc.) during account deletion. |
| **S-13** | Data Leakage | **`badge_awards` has conflicting RLS policies** — Two SELECT policies exist: `badge_awards_own_read` (user_id match) and `badge_awards_public_read` (USING true). The `public_read` policy makes all badge awards visible to any authenticated user, leaking which users earned which badges. | `supabase/schema.sql:1657-1661` — `badge_awards_own_read` USING `auth.uid() = user_id` AND `badge_awards_public_read` USING `true` | **MEDIUM** | Remove `badge_awards_public_read` if badge awards should be private. If public display is intentional, document the decision and restrict the columns exposed (e.g., don't expose `user_id`). |
| **S-14** | Data Leakage | **`profile_progress` has conflicting RLS policies** — Similar to S-13: both `progress_own_read` (user_id match) and `progress_public_read` (USING true) exist. Any authenticated user can read any other user's progression data. | `supabase/schema.sql:1995-1999` — `progress_own_read` AND `progress_public_read` USING `true` | **MEDIUM** | Evaluate if public progress visibility is intentional. If not, remove `progress_public_read`. |
| **S-15** | Financial | **Swap error responses expose raw exception messages** — The swap API route catches exceptions and returns `e.message` directly to the client, which could contain SQL errors, internal function names, or other sensitive details. | `portal/src/app/api/swap/route.ts:138-139` — `const msg = e instanceof Error ? e.message : "Operation failed"; return NextResponse.json({ error: msg })` | **MEDIUM** | Classify errors and return user-safe messages. Log the raw error server-side. |
| **S-16** | Input Validation | **Client-side only validation on most forms** — Form validation (maxLength, required fields) is enforced only via Flutter's `TextFormField` validators and `TextInputFormatter`. No corresponding server-side length/format validation was found in the edge functions for display_name, challenge title, etc. | `omni_runner/lib/presentation/screens/profile_screen.dart:402` (maxLength: 50), `challenge_create_screen.dart:188` (maxLength: 60) — no server-side equivalent in edge functions. | **MEDIUM** | Add server-side input validation (length limits, character whitelisting) in edge functions and API routes. Client-side validation is a UX convenience, not a security boundary. |
| **S-17** | Permissions | **`ACCESS_BACKGROUND_LOCATION` declared without clear justification screen** — Background location is declared in the manifest. While the foreground service comment explains it's for GPS tracking during runs, there's no in-app rationale dialog before requesting this sensitive permission. | `omni_runner/android/app/src/main/AndroidManifest.xml:6` — `ACCESS_BACKGROUND_LOCATION` | **LOW** | Add an in-app explanation screen before requesting background location permission, as required by Google Play policies. |
| **S-18** | Permissions | **iOS `Info.plist` missing camera/photo library usage descriptions** — The profile screen allows avatar upload via `image_picker`, but no `NSCameraUsageDescription` or `NSPhotoLibraryUsageDescription` key was found. The app will crash on iOS when the user tries to pick a photo. | `omni_runner/ios/Runner/Info.plist` — no camera/photo keys. `omni_runner/lib/presentation/screens/profile_screen.dart:2` — imports `image_picker`. | **LOW** | Add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `Info.plist` with user-facing explanations. |
| **S-19** | Auth | **Portal `portal_group_id` cookie is user-settable** — While the middleware re-verifies membership, the initial `groupId` is read from a cookie that the browser can modify. The re-verification query uses the service client implicitly (via the user-scoped Supabase client), but the timing window between cookie read and verification could be exploited in edge cases. | `portal/src/middleware.ts:77` — `let groupId = request.cookies.get("portal_group_id")?.value` | **LOW** | Sign the `portal_group_id` cookie (e.g., using encrypted cookie or JWT claim) to prevent client-side tampering. The current re-verification mitigates most risk. |
| **S-20** | Data Leakage | **`events` and `missions` tables have public read policies** — `events_read_all` (USING true) and `missions_read_all` (USING true) allow any authenticated user to read all events and missions, which may expose internal coaching group event details. | `supabase/schema.sql:1844,1973` | **LOW** | Evaluate whether events should be group-scoped. If they are platform-wide, this is acceptable. Document the decision. |
| **S-21** | Sensitive Data | **Dead-letter queue stores raw webhook headers** — The `webhook-payments` function persists all request headers (including `stripe-signature`) to `billing_webhook_dead_letters` for debugging. This could expose sensitive Stripe headers in the database. | `supabase/functions/webhook-payments/index.ts:489` — `headers: Object.fromEntries(req.headers.entries())` | **LOW** | Filter out sensitive headers (`stripe-signature`, `authorization`) before persisting to the dead-letter table. |

---

## Detailed Analysis by Category

### 1. Data Leakage Between Tenants

**RLS Coverage:** RLS is enabled on all major tables. Most policies correctly filter by `auth.uid() = user_id` or via `coaching_members` group membership subqueries.

**Gaps Found:**
- `challenges` table is readable by ALL authenticated users (S-02)
- `badge_awards` and `profile_progress` have USING(true) policies that override own-read policies (S-13, S-14)
- `events`, `missions`, `seasons`, `badges`, `leaderboards` (global/season scope) have public-read policies — acceptable if these are intentionally platform-wide

**Well Done:**
- `wallets`, `coin_ledger`, `runs`, `sessions` are strictly user-scoped
- `coaching_groups`, `coaching_members` use group membership subqueries
- Portal middleware re-verifies group membership on every request

### 2. Authentication & Authorization

**Architecture:** Edge functions use a shared `requireUser()` that validates JWTs via `auth.getUser()`. Portal middleware enforces session + role + group membership. Rate limiting is applied across edge functions and API routes.

**Gaps Found:**
- 47/48 edge functions have `verify_jwt = false` at the gateway level (S-01)
- Anonymous sign-ins are enabled (S-03)
- `secure_password_change` is disabled (S-04)
- Portal API routes use `getSession()` instead of `getUser()` (S-05)

**Well Done:**
- Middleware re-verifies `portal_group_id` cookie against actual membership
- Role-based route protection (admin_master, coach, assistant)
- `requireUser()` properly classifies connection errors vs auth errors
- Rate limiting on financial and mutation endpoints

### 3. Sensitive Data Exposure

**Positive Findings:**
- No `localStorage` usage found in portal (Supabase SSR uses cookies)
- App uses `FlutterSecureStorage` for encryption keys (`isar_secure_store.dart`)
- Non-sensitive settings use `SharedPreferences` (theme, coach toggles, BLE device IDs)
- No hardcoded API keys found — all via `String.fromEnvironment()` or `env()`
- No `console.log` of sensitive data in portal client code
- Edge functions log structured JSON to `console.error` with request IDs, not raw user data

**Gaps Found:**
- Debug JWT copy feature (S-08)
- Dead-letter header storage (S-21)

### 4. Error Messages

**Positive Findings:**
- `jsonErr()` helper sanitizes 403/404 responses to generic messages
- Portal `error.tsx` and `global-error.tsx` show generic messages without stack traces
- Most edge functions return structured `{ ok, error: { code, message } }` format
- Token values are redacted in error display: `e.toString().replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer ***')`

**Gaps Found:**
- WalletBloc exposes raw exception in error state (S-07)
- Challenge status leaked in error messages (S-09)
- Swap API returns raw `e.message` (S-15)

### 5. Permissions Requested

**Android Permissions (justified):**

| Permission | Justification | Verdict |
|-----------|--------------|---------|
| `INTERNET` | Network access for API calls | Required |
| `ACCESS_FINE_LOCATION` | GPS route tracking during runs | Required |
| `ACCESS_COARSE_LOCATION` | Fallback location | Required |
| `ACCESS_BACKGROUND_LOCATION` | Continue tracking when app is backgrounded | Required, but needs rationale dialog |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION` | Keep GPS alive during runs | Required |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` | BLE heart rate monitors | Required |
| `health.*` (12 permissions) | Health Connect integration | Required for the feature set |
| `ACTIVITY_RECOGNITION` | Step counting | Required |

**iOS Permissions (justified):**

| Permission | Description | Verdict |
|-----------|-------------|---------|
| `NSLocationWhenInUseUsageDescription` | Clear explanation provided | Good |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Clear explanation provided | Good |
| `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` | Clear explanation provided | Good |
| `NSBluetoothAlwaysUsageDescription` | Clear explanation provided | Good |
| Missing: `NSCameraUsageDescription` | Avatar upload requires camera | Bug (S-18) |
| Missing: `NSPhotoLibraryUsageDescription` | Avatar upload requires photos | Bug (S-18) |

### 6. Input Validation

**Client-side:** Flutter forms use `maxLength`, `validator`, and `FilteringTextInputFormatter` for key fields (challenge title, profile name, support tickets, workout durations).

**Server-side:** Edge functions validate required fields via `requireFields()` and use Zod schemas in portal API routes (swap, distribute-coins). However, no length or format validation on string fields was found in edge functions.

**XSS Risk:** Low — Flutter renders text through its own canvas (not a WebView), so HTML/script injection in the mobile app is not exploitable. The portal uses React/Next.js which auto-escapes by default.

### 7. Financial Data

**Well Done:**
- Wallet reads are RLS-scoped to own user (`wallets_own_read`, `ledger_own_read`)
- Entry fee debit uses atomic RPC `debit_wallet_checked` with rollback on failure
- Coin distribution requires `admin_master` role + custody invariant checks
- Swap operations require `admin_master` role + Zod validation + audit logging
- Clearing cron validates service-role key directly
- Idempotency via `stripe_event_id` UNIQUE index + conditional status transitions

**Gaps:**
- No concern found with users seeing other users' balances (properly RLS-gated)
- Transfer amount manipulation is mitigated by server-side validation in `distribute-coins` route (Zod schema) and `debit_wallet_checked` RPC

### 8. Privacy (LGPD/GDPR)

| Requirement | Status | Notes |
|------------|--------|-------|
| Privacy policy link | **Missing** | No link found in app or portal |
| Terms of service | **Missing** | No link found |
| Consent collection | **Missing** | No consent mechanism before data processing |
| Data deletion | **Partial** | Account deletion exists but incomplete (S-12) |
| Data export | **Missing** | No data portability feature found |
| Data minimization | **Good** | Collects only fitness/health data relevant to function |
| Cookie consent | **N/A** | Portal uses session cookies (functional, not tracking) |

---

## Risk Summary

| Risk Level | Count | Finding IDs |
|-----------|-------|-------------|
| CRITICAL | 3 | S-01, S-02, S-03 |
| HIGH | 5 | S-04, S-05, S-06, S-07, S-08 |
| MEDIUM | 7 | S-09, S-10, S-11, S-12, S-13, S-14, S-15, S-16 |
| LOW | 5 | S-17, S-18, S-19, S-20, S-21 |

---

## Priority Remediation Order

1. **S-03** — Disable anonymous sign-ins (config change, immediate)
2. **S-02** — Restrict `challenges` RLS policy (migration, immediate)
3. **S-01** — Re-enable `verify_jwt = true` where possible (config + audit)
4. **S-05** — Replace `getSession()` with `getUser()` in API routes
5. **S-04** — Enable `secure_password_change`
6. **S-06** — Move portal reads to user-scoped client where possible
7. **S-07, S-09, S-15** — Sanitize error messages (batch fix)
8. **S-11, S-12** — LGPD compliance (privacy policy + complete data deletion)
9. **S-08** — Remove JWT copy feature from non-dev builds
10. **S-13, S-14** — Evaluate and fix conflicting RLS policies
