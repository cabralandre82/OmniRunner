# Audit: Security

**Date:** 2026-03-04  
**Scope:** SQL injection, SECURITY DEFINER audit, public endpoints, data exposure, CORS, rate limiting, webhook verification, session management, hardcoded secrets

---

## 1. SQL Injection Analysis

### 1.1 Migrations — String Interpolation in SQL

**Search pattern:** `\$\{.*\}` in `supabase/migrations/*.sql`

**Result:** No string interpolation found in any migration file. All SQL uses parameterized queries via `$1`, `$2`, etc., or PL/pgSQL variables. ✅ **Clean.**

### 1.2 Edge Functions — Unsanitized Parameters

All edge functions use the Supabase client SDK (`.from().select().eq()`, `.rpc()`) which parameterizes all values automatically. No raw SQL string construction found.

**One notable pattern:**

| File | Pattern | Risk |
|------|---------|------|
| `strava-register-webhook/index.ts:47` | `` `https://www.strava.com/api/v3/push_subscriptions?client_id=${clientId}&client_secret=${clientSecret}` `` | **Low** — These are server-side env vars, not user input. No injection risk, but the secret appears in the URL query string (could appear in logs). Recommend using POST body instead. |

### 1.3 Flutter Client

No raw SQL queries found in Flutter code. All database access goes through the Supabase Dart SDK with parameterized builders.

**Verdict:** ✅ No SQL injection vulnerabilities found.

---

## 2. SECURITY DEFINER Audit

### 2.1 Coverage Summary

| Metric | Count |
|--------|-------|
| Total SECURITY DEFINER occurrences across all migrations | ~95+ |
| Migrations with `SET search_path` | 25 files |
| Dedicated hardening migrations | 2 (`security_definer_hardening_remaining`, `security_hardening_legacy_rpcs`) |

### 2.2 Functions WITH `SET search_path` ✅

All functions created in these migrations properly pair SECURITY DEFINER with `SET search_path`:

- `20260304400000_wearables.sql` — `fn_generate_workout_payload`, `fn_import_execution` → `SET search_path = public, pg_temp` ✅
- `20260304800000_trainingpeaks_integration.sql` — both RPCs → `SET search_path = public, pg_temp` ✅
- `20260305000000_workout_delivery.sql` — 4 RPCs → `SET search_path = public` ✅
- `20260304500000_analytics_advanced.sql` — 2 RPCs → `SET search_path = public, pg_temp` ✅
- `20260304300000_workout_financial_integration.sql` → `SET search_path = public, pg_temp` ✅
- `20260304200000_financial_engine.sql` — 2 RPCs → `SET search_path = public, pg_temp` ✅
- `20260304100000_workout_builder.sql` → `SET search_path = public, pg_temp` ✅
- `20260303800000_kpi_attendance_integration.sql` — 2 RPCs → `SET search_path = public, pg_temp` ✅
- `20260303600000_announcements.sql` — 2 RPCs → `SET search_path = public, pg_temp` ✅
- `20260303500000_crm_tags_notes_status.sql` → `SET search_path = public, pg_temp` ✅
- `20260303400000_training_sessions_attendance.sql` — 2 RPCs → `SET search_path = public, pg_temp` ✅
- `20260303300000_fix_coaching_roles.sql` — 6 RPCs → `SET search_path = public, pg_temp` ✅

### 2.3 Functions WITHOUT `SET search_path` ⚠️

These legacy SECURITY DEFINER functions were created without `SET search_path` and were **later fixed** by dedicated hardening migrations:

| Original Migration | Function | Fixed By |
|--------------------|----------|----------|
| `20260218000000_full_schema.sql` | `handle_new_user`, `handle_new_user_gamification`, `fn_update_group_member_count` (triggers) | **NOT fixed** — triggers are SECURITY DEFINER but no `SET search_path`. Low risk since they run on `auth.users` and `group_members` table events, not user-callable |
| `20260220000000_rpc_helpers.sql` | `increment_rate_limit`, `increment_profile_progress`, `compute_leaderboard_global_weekly` | **NOT fixed** — no corresponding hardening migration found |
| `20260221000030_progression_fields_views.sql` | 4 progression RPCs | **NOT fixed** |
| Various `2026022x` migrations | Multiple RPCs | Partially fixed by `20260303900000_security_definer_hardening_remaining.sql` (6 functions) and `20260304600000_security_hardening_legacy_rpcs.sql` (6 functions) |

**Remaining un-hardened SECURITY DEFINER functions (estimated 15-20):**
- All functions in `20260218000000_full_schema.sql` (3)
- All functions in `20260220000000_rpc_helpers.sql` (3)
- All functions in `20260221000030_progression_fields_views.sql` (4)
- Various functions in `2026022x` migrations not covered by hardening passes
- Functions in `20260228xxx` data-migration/backfill scripts (5+)

**Risk:** Without `SET search_path`, a SECURITY DEFINER function could be tricked into resolving table/function names from a malicious schema if `search_path` is manipulated. This is a known Supabase security lint warning.

**Recommendation:** Create a final hardening migration that applies `ALTER FUNCTION ... SET search_path = public, pg_temp` to ALL remaining SECURITY DEFINER functions.

---

## 3. Public Endpoints (Auth Check Analysis)

### 3.1 verify_jwt Configuration

**All 51 edge functions** except `matchmake` have `verify_jwt = false` in `config.toml`. This means Supabase's gateway does NOT validate JWTs — auth is handled manually inside each function.

### 3.2 Functions Using `requireUser()` (manual JWT validation)

40 out of 51 non-webhook functions use `requireUser()` from `_shared/auth.ts`. This function:
1. Extracts Bearer token from Authorization header
2. Calls `auth.getUser(jwt)` to validate
3. Returns user + service-role DB client

### 3.3 Functions WITHOUT User Auth

| Function | Auth Mechanism | Risk |
|----------|---------------|------|
| `webhook-payments` | Stripe signature verification (`constructEventAsync`) | ✅ Secure |
| `webhook-mercadopago` | Fetches payment from MP API to validate (no HMAC) | ⚠️ See section 7 |
| `strava-webhook` | Strava verify_token for subscription; no auth for POST events | ⚠️ See section 7 |
| `strava-register-webhook` | No auth visible | ⚠️ Should be admin-only |
| `send-push` | No `requireUser` (server-to-server via service_role) | ✅ Expected — not client-facing |
| `notify-rules` | No `requireUser` (cron/server-to-server) | ✅ Expected — not client-facing |
| `trainingpeaks-sync` | No `requireUser` (cron/server) | ✅ Expected |
| `trainingpeaks-oauth` | No JWT auth (browser OAuth redirect flow) | ⚠️ State param is unsigned |
| `validate-social-login` | Unknown — not read in this audit | ⚠️ Needs review |

---

## 4. Sensitive Data Exposure

### 4.1 Tokens in Database

| Table | Column | Concern |
|-------|--------|---------|
| `coaching_device_links` | `access_token`, `refresh_token` | OAuth tokens stored in plaintext. Accessible via RLS (athlete can read own, staff can read group). Staff can see athletes' TP tokens |
| `strava_connections` (assumed) | OAuth tokens | Same pattern |

**Recommendation:** Consider encrypting tokens at rest using `pgcrypto` or moving to a vault. At minimum, ensure staff RLS policy only returns `provider` and `linked_at`, not token columns.

### 4.2 API Responses

No edge function was found to return passwords, tokens, or secrets in responses. The `requireUser()` pattern returns only `user.id` and safe fields. ✅

### 4.3 Error Messages

Some error messages in edge functions include internal details (DB error messages). Example: `webhook-mercadopago` returns `"Failed to fetch payment from MP"` which is acceptable, but DB errors in `trainingpeaks-oauth` return `upsertErr.message` which could leak schema information.

**Recommendation:** Sanitize all error responses to return only error codes, never raw DB messages.

---

## 5. CORS Configuration

**File:** `supabase/functions/_shared/cors.ts`

```typescript
Access-Control-Allow-Origin: *
Access-Control-Allow-Headers: authorization, apikey, content-type
Access-Control-Allow-Methods: POST, OPTIONS
```

| Concern | Rating | Details |
|---------|--------|---------|
| Wildcard origin (`*`) | ⚠️ **Major** | Allows any website to make requests to the edge functions. For a mobile app this is less critical, but the portal is a web app. Recommend restricting to known origins (app deep link scheme + portal domain) |
| Methods limited to POST, OPTIONS | ✅ | GET is not listed, which is fine since most functions are POST-only. However, some functions handle GET requests (health checks, TP OAuth authorize, Strava webhook validation) — these work because CORS applies only to browser-originated requests |
| No credentials support | ✅ | `Access-Control-Allow-Credentials` is not set, which is correct with wildcard origin |

---

## 6. Rate Limiting

### 6.1 Infrastructure

The rate limiting system is well-designed:
- `_shared/rate_limit.ts` calls `increment_rate_limit` RPC (Postgres-backed counter)
- Returns 429 with `Retry-After` header when exceeded
- Falls back to 503 on RPC failure (fail-open is debatable; fail-closed would be safer)

### 6.2 Coverage

**39 functions** use `checkRateLimit`. This includes all user-facing functions:

- All `champ-*` functions ✅
- All `challenge-*` functions ✅
- All `clearing-*` functions ✅
- `create-checkout-session`, `create-checkout-mercadopago` ✅
- `matchmake`, `generate-wrapped`, `generate-running-dna` ✅
- `submit-analytics`, `compute-leaderboard` ✅
- `verify-session`, `evaluate-badges` ✅

### 6.3 Functions WITHOUT Rate Limiting

| Function | Reason | Risk |
|----------|--------|------|
| `webhook-payments` | External webhook | ✅ Protected by signature verification |
| `webhook-mercadopago` | External webhook | ⚠️ No signature verification — could be DDoS'd |
| `strava-webhook` | External webhook | ⚠️ No rate limit — Strava controls volume but a fake caller could flood |
| `send-push`, `notify-rules` | Server-to-server | ✅ Not client-facing |
| `trainingpeaks-sync`, `trainingpeaks-oauth` | Server/OAuth | ⚠️ OAuth endpoint could be abused |
| `delete-account` | Uses `requireUser` | ⚠️ No rate limit found — should be rate-limited |

### 6.4 Auth-Level Rate Limiting

`config.toml` has Supabase auth rate limits configured:
- `sign_in_sign_ups`: 30 per 5 min ✅
- `token_refresh`: 150 per 5 min ✅
- `anonymous_users`: 30 per hour ✅
- `email_sent`: 2 per hour ✅

---

## 7. Webhook Signature Verification

### 7.1 Stripe (`webhook-payments`) ✅

```typescript
event = await stripe.webhooks.constructEventAsync(rawBody, sig, webhookSecret, ...);
```
- Uses `stripe-signature` header ✅
- Uses `constructEventAsync` with `SubtleCryptoProvider` ✅
- Rejects on invalid/missing signature ✅

### 7.2 Mercado Pago (`webhook-mercadopago`) ❌ **NOT VERIFIED**

The function does NOT verify webhook signatures. It:
1. Reads the payment ID from the request body
2. Fetches payment details from MP API using the access token
3. Processes based on the fetched status

**Risk:** While fetching from MP API provides some validation (the payment must exist), an attacker who discovers the endpoint URL could:
- Trigger repeated fetches to the MP API (resource exhaustion)
- Send crafted payment IDs to probe for valid purchases
- Potentially cause race conditions with real webhooks

**Recommendation:** Implement MP's webhook signature verification using `x-signature` header and HMAC-SHA256.

### 7.3 Strava (`strava-webhook`) ⚠️ Partial

- GET (subscription validation): uses `STRAVA_VERIFY_TOKEN` comparison ✅
- POST (event notification): **No signature verification** on the POST body

Strava sends event data as simple JSON without HMAC signatures. The only protection is that the endpoint URL is private. This is standard for Strava's V3 API but carries inherent risk.

---

## 8. Session Management

### 8.1 JWT Configuration (`config.toml`)

| Setting | Value | Assessment |
|---------|-------|------------|
| `jwt_expiry` | 3600 (1 hour) | ✅ Standard |
| `enable_refresh_token_rotation` | true | ✅ Good — prevents token reuse |
| `refresh_token_reuse_interval` | 10 seconds | ✅ Reasonable grace period |
| `minimum_password_length` | 6 | ⚠️ **Weak** — recommend 8+ |
| `password_requirements` | `""` (empty) | ⚠️ **No complexity requirements** |
| `enable_anonymous_sign_ins` | true | ⚠️ Review needed — anonymous users get `authenticated` role |
| `enable_confirmations` (email) | false | ⚠️ Users can sign up without email verification |
| `secure_password_change` | false | ⚠️ Password can be changed without re-authentication |

### 8.2 OAuth Providers

- Google, Apple, Facebook enabled ✅
- Secrets use `env()` references (not hardcoded) ✅
- Google has `skip_nonce_check = true` — this is intentional for mobile but reduces replay protection

---

## 9. Hardcoded Secrets Search

**Search pattern:** `sk_live|sk_test|password|secret` (excluding `.md` and `.lock`)

**Results:**

| File | Pattern | Assessment |
|------|---------|------------|
| `omni_runner/.../groups_screen.dart` | `GroupPrivacy.secret` | ✅ False positive — enum value for secret groups |
| `strava-register-webhook/index.ts:47` | `client_secret=${clientSecret}` | ⚠️ Secret in URL query string (from env var, not hardcoded) |
| `portal/src/lib/webhook.test.ts:71` | `const secret = "hmac_secret_key"` | ✅ Test file — acceptable |

**Verdict:** No hardcoded production secrets found. All sensitive values use environment variables. ✅

---

## 10. Summary: Critical Findings

| # | Finding | Severity | Section |
|---|---------|----------|---------|
| 1 | MercadoPago webhook lacks signature verification | **Critical** | §7.2 |
| 2 | ~15-20 SECURITY DEFINER functions without `SET search_path` | **Major** | §2.3 |
| 3 | CORS uses wildcard origin (`*`) | **Major** | §5 |
| 4 | OAuth tokens stored in plaintext, readable by staff via RLS | **Major** | §4.1 |
| 5 | TrainingPeaks OAuth state parameter not signed | **Major** | §3.3 |
| 6 | Password policy too weak (min 6, no complexity) | **Major** | §8.1 |
| 7 | Email confirmation disabled | **Major** | §8.1 |
| 8 | Strava webhook POST events not signature-verified | **Minor** | §7.3 |
| 9 | `strava-register-webhook` has no auth gate | **Minor** | §3.3 |
| 10 | Anonymous sign-ins enabled — review RLS implications | **Minor** | §8.1 |
| 11 | `delete-account` missing rate limiting | **Minor** | §6.3 |
| 12 | Error messages may leak DB schema info | **Minor** | §4.3 |
