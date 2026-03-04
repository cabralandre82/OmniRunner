# Chaos de Permissões — RLS & Permission Boundaries Report

**Principal QA Engineer — Chaos Testing**  
**Repository:** `/home/usuario/project-running`  
**Scope:** RLS policies, edge functions, portal routes, cross-tenant isolation  
**Date:** 2026-03-04

---

## Executive Summary

Analysis of Row Level Security, cross-user/tenant isolation, authentication boundaries, and privilege escalation risks. **Critical findings:** 42 edge functions use `verify_jwt = false` and rely on manual `requireUser()`—any function that omits `requireUser()` is callable unauthenticated; `webhook-mercadopago` and `webhook-payments` have no JWT (by design); `create-portal-session`, `list-purchases`, and similar correctly enforce `admin_master`. No tables were found without RLS. `group_id` is consistently validated in RPCs and EFs.

---

## 1. CROSS-USER ACCESS

### 1.1 RLS Policy Overview

All major tables have RLS enabled (75+ tables). Policies follow consistent patterns:

| Domain | Pattern | Example |
|--------|---------|---------|
| **Athlete-owned** | `auth.uid() = user_id` (or equivalent) | `sessions`, `wallets`, `profiles`, `workout_delivery_items` (athlete_user_id) |
| **Staff-scoped** | `EXISTS (coaching_members WHERE group_id = <table>.group_id AND user_id = auth.uid() AND role IN ('admin_master','coach','assistant'))` | `coaching_workout_templates`, `workout_delivery_batches` |
| **Platform admin** | `profiles.platform_role = 'admin'` | `coaching_announcements`, `coaching_tags`, etc. |

---

### 1.2 Can Athlete A See Athlete B's Data?

| Table | Athlete A → B | RLS Clause |
|-------|---------------|------------|
| `sessions` | ❌ No | `auth.uid() = user_id` |
| `wallets` | ❌ No | Own wallet only |
| `coin_ledger` | ❌ No | Own ledger only |
| `workout_delivery_items` | ❌ No | `athlete_user_id = auth.uid()` for SELECT |
| `coaching_workout_assignments` | ❌ No | Athlete can only SELECT where `athlete_user_id = auth.uid()` AND member of group |
| `challenge_participants` | ⚠️ Partial | User can see all participants of challenges they are in; RLS on `challenges` restricts which challenges are visible |
| `profiles` | ⚠️ Depends | Profile visibility depends on policy; many profiles may be publicly readable for display names/avatars |

**Verdict:** Athletes are isolated from each other for sensitive data (sessions, wallet, ledger, delivery items). Challenge/leaderboard data intentionally shares participant info within a challenge.

---

### 1.3 Can Coach of Group X See Data from Group Y?

| Table | Coach X → Group Y | RLS Clause |
|-------|-------------------|-------------|
| `coaching_workout_templates` | ❌ No | `cm.group_id = coaching_workout_templates.group_id` |
| `coaching_workout_assignments` | ❌ No | Same |
| `workout_delivery_batches` | ❌ No | `cm.group_id = workout_delivery_batches.group_id` |
| `billing_purchases` | ❌ No | `admin_master` only, `cm.group_id = billing_purchases.group_id` |
| `coaching_members` | ❌ No | Staff sees only their group's members |
| `custody_accounts` | ❌ No | `custody_own_group_read` — member of group |
| `clearing_events` | ⚠️ Both groups | `clearing_events_group_read` — member of debtor OR creditor group; a coach sees only cases involving their group |

**Verdict:** Staff is scoped to `group_id` via `coaching_members`. No policy allows access to another group's data.

---

### 1.4 Tables Without RLS

**Finding:** No tables were found with `DISABLE ROW LEVEL SECURITY` or without `ENABLE ROW LEVEL SECURITY` in migrations. All sensitive tables have RLS enabled.

---

## 2. CROSS-TENANT ISOLATION

### 2.1 group_id Consistency

| Layer | group_id Source | Validated Against |
|-------|-----------------|-------------------|
| **RPCs** | Parameter `p_group_id` | `coaching_members` — caller must be staff of that group |
| **Edge Functions** | Body `group_id` | `coaching_members` — user must be member with required role |
| **Portal** | Cookie `portal_group_id` | Re-verified against `coaching_members` on each request |

---

### 2.2 Can User Tamper with group_id in Requests?

| Endpoint | Body Param | Validation |
|----------|------------|------------|
| `fn_create_delivery_batch` | `p_group_id` | RPC checks `coaching_members(group_id, auth.uid())` for staff role |
| `fn_generate_delivery_items` | `p_batch_id` | Derives `group_id` from batch; checks staff of that group |
| `list-purchases` | `group_id` | EF checks `coaching_members(group_id, user.id)` for `admin_master` |
| `create-portal-session` | `group_id` | EF checks `admin_master` for that group |
| `create-checkout-session` | `group_id` | EF checks `admin_master` |
| `fn_coaching_feed` | Implicit | RPC uses `auth.uid()` to resolve group; no client-supplied group_id |

**Verdict:** All RPCs and EFs that accept `group_id` validate membership. Tampering with `group_id` returns 403 if the user is not a member of that group.

---

### 2.3 RPC group_id Validation Patterns

```sql
-- Typical pattern (e.g. fn_create_delivery_batch)
SELECT cm.role INTO v_role FROM coaching_members cm
WHERE cm.group_id = p_group_id AND cm.user_id = auth.uid() LIMIT 1;
IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
  RAISE EXCEPTION 'forbidden';
END IF;
```

Consistently applied in: `fn_create_delivery_batch`, `fn_generate_delivery_items`, `fn_mark_item_published`, `fn_assign_workout`, `fn_push_to_trainingpeaks`, etc.

---

## 3. UNAUTHENTICATED ACCESS

### 3.1 Edge Functions — verify_jwt = false

All edge functions except `matchmake` have `verify_jwt = false` in `supabase/config.toml`. Supabase gateway does **not** validate JWTs. Auth is done manually inside each function.

| Function | Auth Mechanism | Unauthenticated Call? |
|----------|----------------|------------------------|
| `webhook-payments` | None (Stripe signature) | ⚠️ Anyone can POST; Stripe signature verification blocks invalid payloads |
| `webhook-mercadopago` | Optional HMAC (mpWebhookSecret) | ⚠️ If HMAC not configured, anyone can POST; MP API fetch mitigates |
| `clearing-cron` | `Authorization: Bearer <serviceKey>` | ❌ Rejects non–service-key |
| `auto-topup-cron` | Service key check | ❌ Rejects non–service-key |
| `lifecycle-cron` | Service key check | ❌ Rejects non–service-key |
| `reconcile-wallets-cron` | Service key check | ❌ Rejects non–service-key |
| `eval-verification-cron` | Service key check | ❌ Rejects non–service-key |
| `create-checkout-session` | `requireUser()` | ❌ 401 without JWT |
| `list-purchases` | `requireUser()` | ❌ 401 without JWT |
| `create-portal-session` | `requireUser()` | ❌ 401 without JWT |
| `challenge-join` | `requireUser()` | ❌ 401 without JWT |
| `set-user-role` | `requireUser()` | ❌ 401 without JWT |
| (All other user-facing EFs) | `requireUser()` | ❌ 401 without JWT |

**Risk:** Any EF with `verify_jwt = false` that **does not** call `requireUser()` or equivalent is callable without authentication. Audit shows all user-facing EFs use `requireUser()`.

---

### 3.2 Portal API Routes

| Route | Auth | Notes |
|-------|------|-------|
| `/api/health` | Public | In `PUBLIC_ROUTES`; returns status only; uses service client for DB connectivity check |
| `/api/auth/callback` | Public | Supabase OAuth callback |
| `/api/platform/*` | Session + `platform_role = 'admin'` | Middleware enforces |
| All other `/api/*` | Session + staff membership | Middleware enforces |

**Middleware:** `portal/src/middleware.ts` — verifies session, re-validates `portal_group_id` against `coaching_members`, enforces `ADMIN_ONLY_ROUTES` and `ADMIN_PROFESSOR_ROUTES`.

---

### 3.3 Public Endpoints That Should Be Private

| Endpoint | Current | Assessment |
|----------|---------|------------|
| `/api/health` | Public | ✅ Acceptable — health checks are typically public; no sensitive data |
| `/challenge/*` | Public | ✅ Intended for unauthenticated challenge view (e.g. invite links) |
| `/invite/*` | Public | ✅ Invite landing pages |
| `webhook-payments` | No JWT | ✅ By design — Stripe webhooks; signature verified |
| `webhook-mercadopago` | No JWT | ⚠️ MP webhook; HMAC optional; fetch from MP API is primary validation |

---

## 4. PRIVILEGE ESCALATION

### 4.1 Can Athlete Call Staff-Only RPCs?

| RPC | Granted To | Athlete Call? |
|-----|------------|---------------|
| `fn_create_delivery_batch` | `authenticated` | ❌ RPC checks `role IN ('admin_master','coach')` → raises `forbidden` |
| `fn_generate_delivery_items` | `authenticated` | ❌ Same |
| `fn_mark_item_published` | `authenticated` | ❌ Same |
| `fn_assign_workout` | `authenticated`, `service_role` | ❌ Same |
| `fn_fulfill_purchase` | `service_role` only | ❌ Athlete cannot call |
| `get_billing_limits` | `authenticated` | ⚠️ RPC checks staff internally; direct call would fail |
| `fn_approve_join_request` | `authenticated` | ❌ Checks staff role |
| `staff_group_member_ids` | `authenticated` | ⚠️ Returns member IDs; RLS on underlying tables limits impact; used as helper |

**Verdict:** Staff RPCs enforce role checks; athletes receive `forbidden` or equivalent.

---

### 4.2 Can Coach Call admin_master-Only Operations?

| Operation | Required Role | Coach Call? |
|-----------|---------------|-------------|
| `create-portal-session` | `admin_master` | ❌ EF checks `membership.role === 'admin_master'` |
| `list-purchases` | `admin_master` | ❌ Same |
| `create-checkout-session` | `admin_master` | ❌ Same |
| Billing RLS policies | `admin_master` | ❌ Coach has no SELECT on `billing_purchases`, `billing_events` |
| `/credits/*` | `admin_master` | ❌ Portal middleware `ADMIN_ONLY_ROUTES` |

**Verdict:** admin_master-only operations are enforced at EF and RLS level.

---

### 4.3 Role Checks in RPCs

| RPC | Role Check |
|-----|------------|
| `fn_create_delivery_batch` | `admin_master` or `coach` |
| `fn_generate_delivery_items` | `admin_master` or `coach` |
| `fn_mark_item_published` | `admin_master` or `coach` |
| `fn_athlete_confirm_item` | Athlete must be `athlete_user_id` of item |
| `fn_assign_workout` | `admin_master` or `coach` |
| `fn_approve_join_request` | Staff (join_requests_update_staff policy) |
| `fn_push_to_trainingpeaks` | `admin_master` or `coach` |

---

## 5. SERVICE ROLE BYPASS

### 5.1 Where service_role Is Used

| Component | Usage | Bypasses RLS? |
|-----------|-------|---------------|
| `webhook-payments` | DB client | ✅ Yes — required to update `billing_purchases`, call `fn_fulfill_purchase` |
| `webhook-mercadopago` | DB client | ✅ Yes — same |
| `clearing-cron` | DB client | ✅ Yes — backend batch job |
| `auto-topup-check` | DB client | ✅ Yes — invoked after token debit |
| `auto-topup-cron` | DB client | ✅ Yes — scheduled job |
| `process-refund` | DB client | ✅ Yes — platform operation |
| `reconcile-wallets-cron` | DB client | ✅ Yes — batch reconciliation |
| `eval-verification-cron` | DB client | ✅ Yes — verification batch |
| Portal API routes | `createServiceClient()` | ✅ Yes — server-side admin operations |
| `trainingpeaks-sync` | Service client for some ops | ✅ Yes — for cross-user TP sync |

---

### 5.2 Endpoints Using service_role When User-Scoped Might Apply

| Endpoint | Current | Assessment |
|----------|---------|------------|
| `list-purchases` | User-scoped `db` (anon key + JWT) | ✅ Correct — RLS applies, admin_master check in EF |
| `create-checkout-session` | User-scoped | ✅ Correct |
| `create-portal-session` | User-scoped | ✅ Correct |
| `challenge-join` | User-scoped | ✅ Correct |
| `trainingpeaks-sync` | Uses service client for bulk ops | ⚠️ Needs service_role for cross-athlete TP sync; `requireUser()` ensures caller is authenticated |

**Verdict:** service_role is used where RLS must be bypassed (webhooks, crons, platform refunds). User-facing EFs use user-scoped clients where RLS is desired.

---

## 6. requireUser() and Role Checks

### 6.1 Functions Using requireUser()

All 40+ user-facing edge functions call `requireUser(req)` and return 401 if JWT is missing or invalid. Exceptions: webhooks, crons (service-key auth).

---

### 6.2 Functions With verify_jwt = false That Lack requireUser()

| Function | requireUser? | Auth |
|----------|--------------|------|
| `webhook-payments` | No | Stripe signature |
| `webhook-mercadopago` | No | Optional MP HMAC + MP API fetch |
| `clearing-cron` | No | Service key |
| `auto-topup-cron` | No | Service key |
| `lifecycle-cron` | No | Service key |
| `reconcile-wallets-cron` | No | Service key |
| `eval-verification-cron` | No | Service key |
| `auto-topup-check` | No | Invoked internally with service context |
| `notify-rules` | No | Accepts service key or JWT; internal notifier |
| `send-push` | No | Internal; called with context |
| `league-snapshot` | No | Service key (cron) |
| `create-checkout-session` | Yes | requireUser + admin_master |
| `list-purchases` | Yes | requireUser + admin_master |
| ... (all others) | Yes | requireUser |

**Verdict:** Webhooks and crons are intentionally unauthenticated (user JWT); they use signature or service-key validation instead.

---

## 7. Severity Summary

| Severity | Count | Findings |
|----------|-------|----------|
| **CRITICAL** | 0 | — |
| **HIGH** | 0 | — |
| **MEDIUM** | 1 | webhook-mercadopago HMAC optional — defense in depth |
| **LOW** | 2 | 42 EFs with verify_jwt=false — rely on requireUser(); Portal /api/health public |

---

## 8. Recommendations

1. **webhook-mercadopago:** Require HMAC verification when `MERCADOPAGO_WEBHOOK_SECRET` is set; reject requests with invalid signatures.
2. **Defense in depth:** Consider adding `verify_jwt = true` for EFs that always require a user, so the gateway rejects invalid tokens before the function runs (subject to ES256 JWT compatibility).
3. **Audit new EFs:** Ensure every new EF with `verify_jwt = false` calls `requireUser()` or has explicit alternative auth (service key, webhook signature).
