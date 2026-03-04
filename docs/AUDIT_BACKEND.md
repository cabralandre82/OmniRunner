# AUDIT_BACKEND.md — Security Audit of Backend Code

**Audit Date:** 2026-03-04  
**Scope:** All edge functions, RPC functions, and portal queries  
**Repository:** `/home/usuario/project-running`

---

## 1. Edge Functions Inventory (~56 functions)

### 1.1 Auth Pattern Summary

The codebase uses a shared `_shared/auth.ts` module (`requireUser()`) that:

1. Extracts the Bearer JWT from the Authorization header
2. Calls `supabase.auth.getUser(jwt)` to validate it server-side
3. Returns the authenticated user and a **service-role DB client**

**CRITICAL FINDING (SEVERITY: HIGH):** `requireUser()` validates the JWT correctly but returns a **service-role** Supabase client (`db`), not a user-scoped client. This means **all queries made through `db` bypass RLS**. The functions rely on application-level authorization checks (membership role lookups) instead of database-level RLS. While the checks are consistently implemented, any missed check would grant unrestricted service-role access.

### 1.2 Financial Functions

| Function | Auth | Rate Limit | Validation | Role Check | Idempotent | Notes |
|---|---|---|---|---|---|---|
| `clearing-confirm-received` | JWT ✅ | 30/60s ✅ | case_id ✅ | admin_master/coach of to_group ✅ | ✅ | Conditional update on status |
| `clearing-confirm-sent` | JWT ✅ | 30/60s ✅ | case_id ✅ | admin_master/coach of from_group ✅ | ✅ | Conditional update on status |
| `clearing-cron` | service_role ✅ | N/A | N/A | Token === serviceKey ✅ | ✅ | Weekly clearing aggregation |
| `clearing-open-dispute` | JWT ✅ | 10/60s ✅ | case_id ✅ | admin_master/coach of either group ✅ | ✅ | Status guard |
| `token-create-intent` | JWT ✅ | 60/60s ✅ | group_id, type, amount, nonce, expires_at ✅ | staff (admin_master/coach/assistant) ✅ | ✅ via nonce unique | Daily limit + inventory check |
| `token-consume-intent` | JWT ✅ | 30/60s ✅ | nonce ✅ | Affiliation check ✅ | ✅ claim-then-execute | Atomic OPEN→CONSUMED + daily limits |
| `create-checkout-session` | JWT ✅ | 10/60s ✅ | product_id, group_id ✅ | admin_master only ✅ | N/A | Stripe Checkout |
| `create-checkout-mercadopago` | JWT ✅ | 10/60s ✅ | product_id, group_id ✅ | admin_master only ✅ | N/A | MercadoPago Checkout |
| `create-portal-session` | JWT ✅ | 10/60s ✅ | group_id ✅ | admin_master only ✅ | N/A | Stripe Billing Portal |
| `webhook-payments` | Stripe sig ✅ | N/A | Signature verification ✅ | N/A (webhook) | ✅ 3-layer (L1/L2/L3) | Handles checkout.session.completed, refunds, disputes |
| `webhook-mercadopago` | N/A ⚠️ | N/A | Fetches payment from MP API ✅ | N/A (webhook) | ✅ 2-layer (L1/L2) | **No HMAC signature verification** (see finding below) |
| `process-refund` | service_role ✅ | N/A | refund_request_id ✅ | Token === serviceKey ✅ | N/A | RF-1 inventory check ✅ |
| `reconcile-wallets-cron` | service_role ✅ | N/A | N/A | Token === serviceKey ✅ | ✅ | Drift auto-correction with alerting |
| `list-purchases` | JWT ✅ | 60/60s ✅ | group_id ✅ | admin_master only ✅ | N/A | Read-only |
| `auto-topup-check` | service_role ✅ | N/A | group_id ✅ | Token === serviceKey ✅ | ✅ via cooldown+cap | Off-session Stripe charge |
| `auto-topup-cron` | service_role ✅ | N/A | N/A | Token === serviceKey ✅ | ✅ via check delegation | Iterates enabled groups |

**FINDING F-1 (SEVERITY: MEDIUM):** `webhook-mercadopago` does **not verify any HMAC signature or shared secret** from MercadoPago. It fetches the payment from the MP API using the access token to confirm authenticity, which is a valid alternative pattern, but an attacker who knows a valid `purchase_id` and can guess/enumerate `payment_id` values could trigger fulfillment by sending crafted webhook payloads. The MP API fetch mitigates this significantly since the attacker would need a real approved payment, but the function should still validate the MP webhook secret for defense in depth.

**FINDING F-2 (SEVERITY: LOW):** `token-consume-intent` uses the service-role client returned by `requireUser()`, but the affiliation check at line 145-155 queries `coaching_members` properly. The claim-then-execute pattern (lines 191-215) is correctly atomic via conditional update `WHERE status = 'OPEN'`.

**FINDING F-3 (SEVERITY: LOW):** In `clearing-confirm-received` lines 175-191, the release loop iterates items sequentially. If one `release_pending_to_balance` call fails, items before it are already released. There is no wrapping transaction. However, since this uses service-role client and the RPC is atomic per-call, the risk is minimal.

### 1.3 Auth Functions

| Function | Auth | Rate Limit | Validation | Notes |
|---|---|---|---|---|
| `validate-social-login` | **NONE** ⚠️ | **NONE** ⚠️ | provider/action ✅ | Intentionally unauthenticated (OAuth init). TikTok not yet active. |
| `complete-social-profile` | JWT ✅ | 30/60s ✅ | N/A (body optional) | Upsert on profiles with `onConflict: "id"` ✅ |
| `delete-account` | JWT ✅ | **NONE** ⚠️ | N/A | Deletes own data + auth user. **No rate limiting.** |
| `set-user-role` | JWT ✅ | 20/60s ✅ | role ∈ {ATLETA, ASSESSORIA_STAFF} ✅ | Onboarding state guard ✅ |
| `verify-session` | JWT ✅ | 60/60s ✅ | session_id, user_id, route ✅ | Anti-cheat pipeline. Updates session where user_id = caller ✅ |

**FINDING A-1 (SEVERITY: LOW):** `validate-social-login` has no auth and no rate limiting. Since it only returns a TikTok OAuth URL (and TikTok is currently disabled), the risk is low, but it could be used for enumeration or abuse once enabled.

**FINDING A-2 (SEVERITY: LOW):** `delete-account` has no rate limiting. An attacker with a stolen JWT could repeatedly call it (though after the first successful call the account is deleted). More concerning: it calls `db.auth.admin.deleteUser(uid)` using the service-role client from `requireUser()`, which is correct for the use case.

**FINDING A-3 (SEVERITY: MEDIUM):** `delete-account` does NOT check if the user is an `admin_master` of a coaching group before deletion. An admin_master deleting their account could orphan a coaching group with active members, subscriptions, and financial data.

### 1.4 Sync Functions

| Function | Auth | Rate Limit | Validation | Notes |
|---|---|---|---|---|
| `strava-webhook` | Verify token (GET) / **NONE** (POST) ⚠️ | **NONE** | JSON parse ✅ | External webhook. Uses service-role client. |
| `strava-register-webhook` | **Implicit** (described as service_role but not checked) ⚠️ | **NONE** | callback_url ✅ | One-time setup. |
| `trainingpeaks-oauth` | **NONE** (OAuth flow) | **NONE** ⚠️ | action param ✅ | Feature flag gate ✅. State = "userId:groupId" passed in OAuth state. |
| `trainingpeaks-sync` | **NONE** ⚠️ | **NONE** ⚠️ | action param ✅ | Feature flag gate ✅. Uses service-role client for all operations. |

**FINDING S-1 (SEVERITY: MEDIUM):** `strava-webhook` POST handler has no authentication. This is standard for webhooks, but Strava provides a subscription ID in the payload that should be validated. The function does not verify `subscription_id` matches the expected value.

**FINDING S-2 (SEVERITY: HIGH):** `trainingpeaks-sync` has **NO authentication at all**. Any caller can POST `{ "action": "push" }` or `{ "action": "pull", "group_id": "..." }` and it will execute operations using the service-role client. It should require either service_role key verification or JWT + staff role check.

**FINDING S-3 (SEVERITY: MEDIUM):** `trainingpeaks-oauth` callback stores OAuth tokens (`access_token`, `refresh_token`) in `coaching_device_links` using the service-role client. The `state` parameter (`userId:groupId`) comes from the OAuth redirect and is not validated against any signed/encrypted value. An attacker could craft a malicious callback URL with a different `userId:groupId` to link their TrainingPeaks account to another user's profile.

**FINDING S-4 (SEVERITY: MEDIUM):** `trainingpeaks-oauth` refresh action (`action=refresh`) accepts `user_id` in the POST body with **no auth check**. Any caller can refresh any user's TrainingPeaks token.

**FINDING S-5 (SEVERITY: LOW):** `strava-register-webhook` exposes Strava client credentials in the subscription creation call, which is expected, but the function has no explicit auth check — it just says "requires service_role JWT" in the comment without enforcement.

### 1.5 Remaining Edge Functions

| Function | Auth | Rate Limit | Key Notes |
|---|---|---|---|
| `calculate-progression` | JWT ✅ | ✅ | Calculates XP/level progression |
| `challenge-accept-group-invite` | JWT ✅ | ✅ | Staff role check ✅ |
| `challenge-create` | JWT ✅ | ✅ | Validates stake, metric, participants |
| `challenge-get` | JWT ✅ | ✅ | Read-only, participant check |
| `challenge-invite-group` | JWT ✅ | ✅ | Admin_master check ✅ |
| `challenge-join` | JWT ✅ | ✅ | Verification gate ✅, wallet check |
| `challenge-list-mine` | JWT ✅ | ✅ | Filtered by user |
| `champ-accept-invite` | JWT ✅ | ✅ | Staff role check ✅ |
| `champ-activate-badge` | JWT ✅ | ✅ | Badge inventory check |
| `champ-cancel` | JWT ✅ | ✅ | Host admin_master only ✅ |
| `champ-create` | JWT ✅ | ✅ | Admin_master check ✅ |
| `champ-enroll` | JWT ✅ | ✅ | Badge + invite check ✅ |
| `champ-invite` | JWT ✅ | ✅ | Host admin_master only ✅ |
| `champ-lifecycle` | service_role ✅ | N/A | Cron: starts/ends championships |
| `champ-list` | JWT ✅ | ✅ | Read-only |
| `champ-open` | JWT ✅ | ✅ | Admin_master check ✅ |
| `champ-participant-list` | JWT ✅ | ✅ | Read-only |
| `champ-update-progress` | service_role ✅ | N/A | Cron: updates championship leaderboards |
| `compute-leaderboard` | service_role ✅ | N/A | Cron: leaderboard computation |
| `eval-athlete-verification` | JWT ✅ | ✅ | Calls RPC, fire-and-forget |
| `evaluate-badges` | JWT ✅ | ✅ | Badge evaluation for user |
| `eval-verification-cron` | service_role ✅ | N/A | Cron: re-evaluates flagged athletes |
| `generate-running-dna` | JWT ✅ | ✅ | Profile analytics |
| `generate-wrapped` | JWT ✅ | ✅ | Year-in-review generation |
| `league-list` | JWT ✅ | ✅ | Read-only |
| `league-snapshot` | service_role ✅ | N/A | Cron: weekly league scoring |
| `lifecycle-cron` | service_role ✅ | N/A | Cron: challenge lifecycle |
| `matchmake` | JWT ✅ | ✅ | Queue-based matchmaking |
| `notify-rules` | service_role ✅ | N/A | Internal push notification dispatch |
| `send-push` | service_role ✅ | N/A | FCM push |
| `settle-challenge` | JWT/service ✅ | ✅ | Challenge settlement with wallet ops |
| `submit-analytics` | JWT ✅ | ✅ | Analytics event ingestion |

### 1.6 Edge Function Summary

- **Total functions:** 56 (excluding `_shared`)
- **With JWT auth:** 38
- **With service_role auth:** 14
- **With NO auth:** 4 (`validate-social-login`, `trainingpeaks-sync`, `trainingpeaks-oauth`, `strava-register-webhook`)
- **With rate limiting:** 38 (all JWT-authed functions)
- **Health endpoint:** All functions have `/health` endpoint ✅
- **CORS handling:** All functions call `handleCors()` ✅
- **Error classification:** Consistent use of `classifyError()` ✅
- **Observability:** All functions log via `logRequest()`/`logError()` ✅

---

## 2. RPC Functions (Database Functions)

### 2.1 Security Properties

All RPC functions found are `SECURITY DEFINER`. A dedicated hardening migration (`20260304600000_security_hardening_legacy_rpcs.sql`) applied `REVOKE ALL FROM PUBLIC` + `GRANT TO authenticated/service_role` to key functions. A second pass (`20260303900000_security_definer_hardening_remaining.sql`) did the same for remaining functions.

| Function | SECURITY DEFINER | SET search_path | REVOKE/GRANT | Validates Caller | Group Isolation | Idempotent | Uses Transaction |
|---|---|---|---|---|---|---|---|
| `fn_create_assessoria` | ✅ | ✅ public, pg_temp | ✅ authenticated | ✅ auth.uid() | N/A (creates new) | ✅ | Implicit |
| `fn_request_join` | ✅ | ✅ public, pg_temp | ✅ authenticated | ✅ auth.uid() | ✅ group_id param | ✅ | Implicit |
| `fn_approve_join_request` | ✅ | ✅ public, pg_temp | ✅ authenticated | ✅ staff of group | ✅ via request lookup | ✅ | Implicit |
| `fn_reject_join_request` | ✅ | ✅ public, pg_temp | ✅ authenticated | ✅ staff of group | ✅ via request lookup | ✅ | Implicit |
| `fn_remove_member` | ✅ | ✅ public, pg_temp | ✅ authenticated | ✅ admin_master | ✅ group_id param | ✅ | Implicit |
| `fn_switch_assessoria` | ✅ | ❌ **MISSING** | ❌ | ✅ auth.uid() | ✅ | ✅ | Implicit |
| `fn_fulfill_purchase` | ✅ | ✅ public | ❌ (service_role use) | N/A (service_role) | ✅ via purchase lookup | ✅ FOR UPDATE lock | ✅ Explicit |
| `fn_credit_badge_inventory` | ✅ | ✅ public | ❌ | N/A (service_role) | ✅ group_id param | ✅ | Implicit |
| `fn_decrement_badge_inventory` | ✅ | ✅ public | ❌ | N/A (service_role) | ✅ group_id param | ✅ CHECK constraint | Implicit |
| `decrement_token_inventory` | ✅ | ❌ **MISSING** | ❌ | N/A (service_role) | ✅ group_id param | ✅ CHECK constraint | Implicit |
| `increment_wallet_balance` | ✅ | ❌ **MISSING** | ❌ | N/A (service_role) | ✅ user_id param | ✅ | Implicit |
| `increment_wallet_pending` | ✅ | ❌ **MISSING** | ❌ | N/A (service_role) | ✅ user_id param | ✅ | Implicit |
| `release_pending_to_balance` | ✅ | ❌ **MISSING** | ❌ | N/A (service_role) | ✅ user_id param | ✅ | Implicit |
| `execute_burn_atomic` | ✅ | ✅ (hardening migration) | ✅ service_role | N/A (service_role) | ✅ user_id param | ✅ | ✅ Explicit |
| `eval_athlete_verification` | ✅ | ❌ **MISSING** | ❌ | N/A (p_user_id param) | ✅ user_id param | ✅ | Implicit |
| `reconcile_wallet` | ✅ | ✅ public | ❌ | N/A (service_role) | ✅ user_id param | ✅ | Implicit |
| `reconcile_all_wallets` | ✅ | ✅ public | ❌ | N/A (service_role) | N/A (all wallets) | ✅ | ✅ |
| `compute_leaderboard_*` | ✅ | ❌ **MISSING** | ❌ | N/A | Param-scoped | ✅ | Implicit |
| `fn_mark_attendance` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ group_id param | ✅ | Implicit |
| `fn_issue_checkin_token` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ session_id scoped | ✅ | Implicit |
| `fn_mark_announcement_read` | ✅ | ✅ public, pg_temp | ❌ | ✅ auth.uid() member check | ✅ | ✅ | Implicit |
| `fn_upsert_member_status` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ group_id param | ✅ | Implicit |
| `fn_assign_workout` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ group_id derived | ✅ | Implicit |
| `fn_create_delivery_batch` | ✅ | ✅ public | ❌ | ✅ staff check | ✅ group_id param | ✅ | Implicit |
| `fn_generate_delivery_items` | ✅ | ✅ public | ❌ | ✅ staff check | ✅ batch_id scoped | ✅ | Implicit |
| `fn_update_subscription_status` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ subscription scoped | ✅ | Implicit |
| `fn_create_ledger_entry` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ group_id param | ✅ | Implicit |
| `compute_coaching_kpis_daily` | ✅ | ✅ public, pg_temp | ❌ | N/A (service_role) | Per-group iteration | ✅ | Implicit |
| `compute_coaching_alerts_daily` | ✅ | ✅ public, pg_temp | ❌ | N/A (service_role) | Per-group iteration | ✅ | Implicit |
| `fn_push_to_trainingpeaks` | ✅ | ✅ public, pg_temp | ❌ | ✅ staff check | ✅ assignment scoped | ✅ | Implicit |

**FINDING R-1 (SEVERITY: MEDIUM):** Several older SECURITY DEFINER functions lack `SET search_path`. Affected functions include:
- `fn_switch_assessoria`
- `decrement_token_inventory` / `increment_inventory_burned`
- `increment_wallet_balance` / `increment_wallet_pending` / `release_pending_to_balance`
- `eval_athlete_verification` / `get_verification_state` / `is_user_verified`
- `compute_leaderboard_assessoria` / `compute_leaderboard_championship` / `compute_leaderboard_global`
- `increment_profile_progress` / `fn_update_streak`
- Various `fn_*` from `progression_fields_views`, `invite_codes`, `staff_onboarding`

Without `SET search_path`, a SECURITY DEFINER function could be exploited via search_path injection (e.g., creating a malicious `pg_temp` schema function with the same name as a referenced function). The hardening migration `20260303900000` fixed some of these but not all.

**FINDING R-2 (SEVERITY: LOW):** Most financial RPCs called by edge functions (e.g., `decrement_token_inventory`, `increment_wallet_balance`) lack explicit `REVOKE/GRANT`. They are called via service_role client which bypasses grants anyway, but `PUBLIC` still has EXECUTE access, meaning a crafty authenticated user could call them directly via PostgREST if they know the function signatures.

**FINDING R-3 (SEVERITY: INFO):** `fn_get_user_id_by_email` has `SET search_path = ''` (empty string) which is the most restrictive — good practice. This is an exception to the pattern of `public, pg_temp`.

---

## 3. Portal Queries Analysis

### 3.1 Client Types Used

The portal uses three Supabase client types:

| Client | Created By | Key Used | Bypasses RLS |
|---|---|---|---|
| `createClient()` (server.ts) | `createServerClient` from `@supabase/ssr` | `ANON_KEY` | **No** — respects RLS |
| `createServiceClient()` (service.ts) | `createClient` from `@supabase/supabase-js` | `SERVICE_ROLE_KEY` | **Yes** |
| `createAdminClient()` (admin.ts) | `createClient` from `@supabase/supabase-js` | `SERVICE_ROLE_KEY` | **Yes** |

### 3.2 Pages Using Service Client (RLS Bypass)

| Page/Route | Client | Tables Queried | group_id Filter | Notes |
|---|---|---|---|---|
| `(portal)/communications` | service ⚠️ | coaching_announcements, coaching_announcement_reads, coaching_members, profiles | ✅ `.eq("group_id", groupId)` | Uses service client for cross-table read counts |
| `(portal)/fx` | service ⚠️ | custody_deposits, custody_withdrawals, platform_fee_config, custody_accounts | ✅ `.eq("group_id", groupId)` | Financial data |
| `(portal)/verification` | service ⚠️ | coaching_members, athlete_verification | ✅ `.eq("group_id", groupId)` | Reads verification status for group athletes |
| `(portal)/risk` | service ⚠️ | coaching_alerts | ✅ `.eq("group_id", groupId)` | Alert data |
| `(portal)/distributions` | service ⚠️ | Multiple | ✅ | Distribution history |
| `(portal)/clearing` | service ⚠️ | clearing_settlements, clearing_events | ✅ group scoped | Clearing data |
| `(portal)/credits` | service ⚠️ | billing_customers | ✅ `.eq("group_id", groupId)` | Customer data for badge inventory |
| `(portal)/workouts/analytics` | service ⚠️ | Multiple | ✅ group scoped | Workout analytics |
| `(portal)/settings` | service ⚠️ | billing_auto_topup_settings, platform_fee_config, custody_accounts | ✅ | Settings page |
| `(portal)/badges` | service ⚠️ | billing_customers, coaching_badge_inventory | ✅ | Badge purchase UI |
| `(portal)/custody` | service ⚠️ | Multiple custody tables | ✅ | Custody dashboard |
| `(portal)/swap` | service ⚠️ | swap_orders, coaching_groups | ✅ | Swap page |
| `(portal)/audit` | service ⚠️ | clearing_events, clearing_settlements | ✅ | Audit log |
| `(portal)/athletes` | service ⚠️ | coaching_members, profiles, wallets, sessions | ✅ | Athlete list |
| `(portal)/engagement` | service ⚠️ | coaching_members, sessions, profiles | ✅ | Engagement dashboard |
| `(portal)/dashboard` | service ⚠️ | Multiple | ✅ | Main dashboard |
| `(portal)/attendance-analytics` | service ⚠️ | coaching_training_sessions, coaching_training_attendance | ✅ | Attendance analytics |
| `platform/*` pages | admin ⚠️ | Various (all tables) | **Varies** | Platform admin — intentional bypass |
| API routes (`/api/*`) | service ⚠️ | Various | ✅ (most check membership) | Server-side actions |

### 3.3 Pages Using Anon Client (RLS-Aware)

| Page | Client | Tables Queried | Notes |
|---|---|---|---|
| `(portal)/layout.tsx` | anon ✅ | profiles, coaching_members, coaching_groups, portal_branding, custody_accounts | Filtered by auth.uid() and group_id |
| `(portal)/delivery/page.tsx` | anon ✅ | workout_delivery_batches, workout_delivery_items, profiles | group_id filtered |
| `(portal)/trainingpeaks/page.tsx` | anon ✅ | coaching_device_links | group_id filtered |
| `(portal)/billing/page.tsx` | anon ✅ | billing_purchases | group_id filtered |
| `(portal)/crm/*` | anon ✅ | coaching_members, profiles, coaching_member_status, coaching_athlete_tags, coaching_alerts | group_id filtered |
| `(portal)/attendance/page.tsx` | anon ✅ | coaching_training_sessions | group_id filtered |
| `(portal)/workouts/*` | anon ✅ | coaching_workout_templates, coaching_workout_assignments | group_id filtered |
| `select-group/page.tsx` | anon ✅ | coaching_members | user_id filtered |

**FINDING P-1 (SEVERITY: MEDIUM):** The portal uses `createServiceClient()` (service-role) for approximately **20+ pages** in the `(portal)/` route group. While all observed queries include `.eq("group_id", groupId)`, the `groupId` comes from a cookie (`portalGroupId`). An attacker who modifies this cookie could query data from any group since the service-role client bypasses RLS. The portal layout does verify the user's membership in the group for navigation, but individual page data fetches using service client trust the cookie without re-verification.

**FINDING P-2 (SEVERITY: HIGH):** `platform/*` pages use `createAdminClient()` (service-role) to query ALL data across ALL groups (no group_id filter). This is intentional for platform admins, but the only gate is checking `profiles.platform_role = 'admin'` in the layout. If any page under `platform/` is accessible without passing through the layout gate (e.g., direct API call to a platform-only API route), it would expose cross-group data.

**FINDING P-3 (SEVERITY: LOW):** API routes like `/api/distribute-coins`, `/api/clearing`, `/api/export/*` use `createServiceClient()` but verify the caller's membership role against the group before executing operations. This is a correct pattern but relies on application-level checks rather than database-level RLS.

---

## 4. Summary of Critical Findings

| ID | Severity | Finding |
|---|---|---|
| **S-2** | HIGH | `trainingpeaks-sync` has NO authentication — any caller can push/pull workouts |
| **P-2** | HIGH | Platform admin pages use service-role with only application-level admin check |
| **AUTH** | HIGH | `requireUser()` returns service-role client — all edge function queries bypass RLS |
| **F-1** | MEDIUM | `webhook-mercadopago` has no HMAC signature verification |
| **S-3** | MEDIUM | `trainingpeaks-oauth` callback state parameter is unsigned — account linking hijack possible |
| **S-4** | MEDIUM | `trainingpeaks-oauth` refresh action has no auth check |
| **A-3** | MEDIUM | `delete-account` doesn't check admin_master status before orphaning groups |
| **R-1** | MEDIUM | Multiple SECURITY DEFINER functions lack `SET search_path` |
| **P-1** | MEDIUM | Portal pages using service-role client trust group_id from cookie without re-verification |
| **S-1** | MEDIUM | `strava-webhook` doesn't validate subscription_id |
| **R-2** | LOW | Financial RPCs lack REVOKE/GRANT — callable by authenticated users via PostgREST |
| **A-1** | LOW | `validate-social-login` has no auth or rate limiting |
| **A-2** | LOW | `delete-account` has no rate limiting |
| **S-5** | LOW | `strava-register-webhook` has no auth enforcement |

### Recommendations

1. **Add auth to `trainingpeaks-sync`** — require service_role key verification
2. **Sign the OAuth state parameter** in `trainingpeaks-oauth` with HMAC to prevent callback hijack
3. **Add MercadoPago webhook signature verification** using the `x-signature` header
4. **Add `SET search_path = public, pg_temp`** to all remaining SECURITY DEFINER functions
5. **Re-verify group membership** in portal pages that use service client, or switch to anon client + RLS
6. **Add rate limiting** to `delete-account`, `validate-social-login`
7. **Add admin_master orphan check** to `delete-account` flow
8. **Consider switching edge functions** from service-role client to user-scoped client where RLS policies exist
