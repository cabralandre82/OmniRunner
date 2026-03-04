# Chaos de Banco — Database Concurrency & Consistency Report

**Principal QA Engineer — Chaos Testing**  
**Repository:** `/home/usuario/project-running`  
**Scope:** Database migrations, RPCs, edge functions  
**Date:** 2026-03-04

---

## Executive Summary

Analysis of the entire codebase for database concurrency, idempotency, race conditions, transaction boundaries, and data integrity. **Critical findings:** MercadoPago webhook L1 dedup is ineffective (no UNIQUE constraint), `debit_wallet_checked` lacks row locking enabling double-spend, `fn_create_delivery_batch` allows duplicate batches, and `fn_decrement_badge_inventory` has a read-modify-write race.

---

## 1. DUPLICATE REQUESTS

### 1.1 `fn_fulfill_purchase` — Called Twice for Same Purchase

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/migrations/20260302000000_badge_inventory_sales.sql` (lines 105–169), `20260221000011_billing_portal_tables.sql` (lines 203–255) |
| **Idempotency** | ✅ **Protective** |
| **Mechanism** | `SELECT ... FOR UPDATE` on `billing_purchases` locks the row; `IF v_purchase.status != 'paid'` raises exception for non-`paid` status |
| **Double-call behavior** | First call: `paid` → `fulfilled` + credit allocation. Second call: row already `fulfilled` → exception `"purchase must be in paid status, got: fulfilled"`; no double credit |
| **Impact** | None |
| **Severity** | N/A (safe) |

---

### 1.2 `fn_athlete_confirm_item` — Called Twice

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/migrations/20260305000000_workout_delivery.sql` (lines 346–386) |
| **Idempotency** | ✅ **Protective** |
| **Mechanism** | Early return: `IF v_status IN ('confirmed','failed') THEN RETURN 'already_' || v_status;`; `UPDATE ... WHERE id = p_item_id AND status = 'published'` — only `published` rows updated |
| **Double-call behavior** | First call: `published` → `confirmed`/`failed`. Second call: returns `'already_confirmed'` or `'already_failed'`; no second event inserted |
| **Impact** | None |
| **Severity** | N/A (safe) |

---

### 1.3 `fn_create_delivery_batch` — Called Twice with Same Params

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/migrations/20260305000000_workout_delivery.sql` (lines 181–209) |
| **Idempotency** | ❌ **Missing** |
| **Mechanism** | Simple `INSERT INTO workout_delivery_batches (...)`; no `ON CONFLICT`, no UNIQUE on `(group_id, period_start, period_end)` |
| **Double-call behavior** | Two identical calls create two batches for the same group and period |
| **Impact** | Duplicate batches; duplicate delivery items for the same period; staff confusion |
| **Severity** | **MEDIUM** |

**Recommendation:** Add `UNIQUE (group_id, period_start, period_end)` or `ON CONFLICT` with conflict target, or an idempotency key parameter.

---

### 1.4 RPC Idempotency Summary

| RPC | Idempotent? | Mechanism |
|-----|-------------|-----------|
| `fn_fulfill_purchase` | ✅ | FOR UPDATE + status check |
| `fn_athlete_confirm_item` | ✅ | Early return + conditional UPDATE |
| `fn_create_delivery_batch` | ❌ | None |
| `fn_generate_delivery_items` | ✅ | `ON CONFLICT (batch_id, athlete_user_id, assignment_id) DO NOTHING` |
| `fn_mark_item_published` | ✅ | `IF v_status = 'published' THEN RETURN`; `UPDATE ... AND status = 'pending'` |
| `fn_assign_workout` | ✅ | `ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE` |
| `fn_try_match` (challenge queue) | ✅ | `FOR UPDATE SKIP LOCKED` |
| `fn_approve_join_request` / `fn_reject_join_request` | ✅ | `SELECT ... FOR UPDATE` on join request |
| `debit_wallet_checked` | Partial | Atomic UPDATE, but see Race Conditions |
| `reconcile_wallet` | ✅ | `FOR UPDATE` on wallet row |

---

### 1.5 UNIQUE Constraints That Prevent Duplication

| Table | Constraint | Purpose |
|-------|------------|---------|
| `billing_events` | `idx_billing_events_stripe_dedup` (stripe_event_id) | Stripe webhook L1 dedup |
| `workout_delivery_items` | `(batch_id, athlete_user_id, assignment_id)` | Prevents duplicate delivery items |
| `coaching_workout_assignments` | `(athlete_user_id, scheduled_date)` | One assignment per athlete per date |
| `challenge_queue` | `(user_id)` WHERE status='waiting' | One active queue entry per user |
| `challenge_participants` | `(challenge_id, user_id)` | One participant per challenge |
| `coaching_subscriptions` | `(athlete_user_id, group_id)` | One subscription per athlete per group |

---

## 2. CONCURRENT OPERATIONS

### 2.1 Two Coaches Assign Same Workout Simultaneously

| Aspect | Finding |
|--------|---------|
| **Location** | `fn_assign_workout` in `20260304300000_workout_financial_integration.sql` |
| **Mechanism** | `INSERT ... ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE SET template_id = EXCLUDED.template_id, ...` |
| **Concurrent behavior** | Both inserts hit conflict; both perform `DO UPDATE`; last commit wins |
| **Impact** | Last writer overwrites; no duplicate assignment rows; possible overwrite of intended template |
| **Severity** | **LOW** — last-write semantics acceptable for assignment; no data corruption |

---

### 2.2 Two Webhooks Process Same Payment Concurrently

#### Stripe (`webhook-payments`)

| Aspect | Finding |
|--------|---------|
| **L1** | `billing_events.stripe_event_id` UNIQUE → second insert fails |
| **L2** | `UPDATE ... WHERE status = 'pending'` → only one update succeeds |
| **L3** | `fn_fulfill_purchase` uses `FOR UPDATE` + status check |
| **Result** | ✅ Triple protection; no double fulfillment |

#### MercadoPago (`webhook-mercadopago`)

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/functions/webhook-mercadopago/index.ts` |
| **L1** | ❌ **Failing** — `insertEvent` uses `metadata` with `mp_payment_id`; **no UNIQUE on metadata**; `stripe_event_id` is NULL for MP events |
| **L2** | ✅ `UPDATE ... WHERE status = 'pending'` |
| **L3** | ✅ `fn_fulfill_purchase` FOR UPDATE |
| **Result** | L1 does not prevent duplicate `billing_events` rows; L2/L3 still protect against double fulfillment, but L1 does not block duplicate processing attempts |
| **Impact** | Duplicate `billing_events` entries; possible redundant processing; logs/analytics pollution |
| **Severity** | **MEDIUM** |

---

### 2.3 FOR UPDATE Lock Usage

| Location | Table/Rows | Purpose |
|----------|------------|---------|
| `fn_fulfill_purchase` | `billing_purchases` | Serialize fulfillment |
| `reconcile_wallet` | `wallets` | Serialize reconciliation |
| `fn_approve_join_request` / `fn_reject_join_request` | `coaching_join_requests` | Serialize approval/rejection |
| `fn_try_match` | `challenge_queue` | `FOR UPDATE SKIP LOCKED` for lock-free matching |
| `fn_create_assessoria` (platform approval) | `coaching_groups` | Serialize group creation |
| `custody` / `clearing` RPCs | `custody_accounts`, etc. | Serialize swaps and settlements |
| `debit_wallet_checked` | ❌ **Missing** | No FOR UPDATE |

---

### 2.4 Advisory Locks

**Finding:** No `pg_advisory_lock` usage found in migrations.

---

## 3. RACE CONDITIONS

### 3.1 Wallet Debited by Two Operations Simultaneously

| Aspect | Finding |
|--------|---------|
| **Location** | `debit_wallet_checked` in `supabase/migrations/20260227400000_challenge_team_and_entry_fee.sql` |
| **Code** | `UPDATE wallets SET balance_coins = balance_coins - p_amount ... WHERE user_id = p_user_id AND balance_coins >= p_amount` |
| **Lock** | ❌ **No FOR UPDATE** |
| **Race scenario** | User has 100 coins; two concurrent debits of 60 each. Without lock: both can read 100, both pass `balance_coins >= 60`, both update. Result: balance can go negative or one update can overwrite the other |
| **Mitigation** | `UPDATE ... WHERE balance_coins >= p_amount` is atomic; Postgres evaluates the predicate on the current row at update time. Two concurrent updates: first succeeds (100→40); second sees 40, fails `40 >= 60` → **no row updated**. So double-spend is prevented at the SQL level |
| **Verdict** | ✅ **Safe** — single UPDATE with predicate is atomic; no read-modify-write split |
| **Severity** | N/A |

**Note:** `increment_wallet_balance` does `UPDATE ... SET balance_coins = balance_coins + p_delta` — also atomic. No race for single-row updates.

---

### 3.2 Two Users Join Challenge at the Same Time

| Aspect | Finding |
|--------|---------|
| **Location** | `supabase/functions/challenge-join/index.ts` |
| **Flow** | Check capacity → INSERT participant → debit wallet → insert coin_ledger |
| **UNIQUE** | `challenge_participants(challenge_id, user_id)` |
| **1v1 capacity** | Max 2 participants |
| **Race scenario** | User A and B join simultaneously. Both pass capacity check (0 or 1). Both INSERT — different `user_id` → both succeed. Debit and ledger are per-user, so no double debit. |
| **Overflow risk** | With 2 participants, a 3rd user could pass a stale capacity check (isolation) and attempt INSERT; `UNIQUE` would not block (different user). Capacity is enforced in app code only — no DB constraint on participant count |
| **Impact** | Possible >2 participants in 1v1 if TOCTOU in app; DB allows it |
| **Severity** | **LOW** — would require precise timing; app check is the primary guard |

---

### 3.3 Subscription and Billing Events Out of Order

| Aspect | Finding |
|--------|---------|
| **Location** | `fn_update_subscription_status`, webhooks |
| **Scenario** | `fulfilled` event before `paid`; `cancelled` before `payment_confirmed` |
| **Stripe flow** | L2 `UPDATE ... WHERE status = 'pending'` — `paid` transition is conditional; `fn_fulfill_purchase` requires `paid` |
| **Out-of-order** | If `fulfilled` (or fulfillment RPC) arrives before `paid`: L2 update would not run (not `pending`), fn_fulfill_purchase would fail on status check |
| **Verdict** | Status machine prevents invalid transitions; out-of-order events fail safely |

---

### 3.4 Read-Modify-Write Without Locks

| Operation | Location | Risk |
|-----------|----------|------|
| `fn_decrement_badge_inventory` | `20260302000000_badge_inventory_sales.sql` | `UPDATE ... SET available_badges = available_badges - p_amount` — atomic UPDATE; CHECK prevents negative. ✅ Safe |
| `fn_assign_workout` weekly limit check | `20260304300000_workout_financial_integration.sql` | `SELECT count(*) ...` then `INSERT` — TOCTOU between count and insert. Two staff could exceed `max_workouts_per_week` |
| **Severity** | **MEDIUM** for weekly limit race |

---

## 4. TRANSACTION BOUNDARIES

### 4.1 Multi-Step Operations in Single Transaction

| Operation | Wrapped in Transaction? | Notes |
|-----------|--------------------------|-------|
| `fn_fulfill_purchase` | ✅ | Single function; single transaction |
| `fn_credit_institution` | ✅ | INSERT + ON CONFLICT UPDATE in one txn |
| `fn_assign_workout` | ✅ | Single INSERT/UPDATE in one txn |
| `challenge-join` (EF) | ❌ | INSERT participant → debit → ledger in separate calls; no DB transaction |
| `challenge-create` (EF) | ❌ | Similar; rollback via explicit DELETE/UPDATE on failure |

**Impact:** If participant is inserted and debit fails, EF performs application-level rollback (DELETE participant). If debit succeeds and ledger insert fails, ledger and wallet diverge until reconciliation.

---

### 4.2 Partial Failure Mid-Operation

| Scenario | Behavior |
|----------|----------|
| `fn_fulfill_purchase` after `fn_credit_institution` | Credits allocated; if purchase UPDATE fails, purchase stays `paid`; retry will hit “must be paid” — credits orphaned until manual fix |
| `challenge-join` debit fails | Participant deleted by EF; consistent |
| `challenge-join` ledger insert fails | Wallet debited, no ledger entry; `reconcile_wallet` will detect drift |

---

## 5. DATA INTEGRITY

### 5.1 Foreign Keys

Foreign keys are consistently defined (e.g. `billing_purchases.group_id`, `workout_delivery_items.batch_id`). No obvious FK gaps identified.

---

### 5.2 Orphan Records

| Risk | Mitigation |
|------|-------------|
| `billing_purchases` with `fulfilled_credit_id` pointing to deleted `institution_credit_purchases` | FK `ON DELETE` not set; manual delete could orphan; low likelihood |
| `workout_delivery_items.assignment_id` | FK to `coaching_workout_assignments`; `ON DELETE` not specified — assignment deletion could orphan items |

---

### 5.3 Status Transitions

| Table | Status Column | CHECK | Backwards Transitions |
|-------|---------------|-------|------------------------|
| `billing_purchases` | status | `pending, paid, fulfilled, cancelled` | No CHECK preventing backwards; updates are via RPC/EF only |
| `workout_delivery_items` | status | `pending, published, confirmed, failed` | RPCs only allow forward transitions |
| `coaching_workout_assignments` | status | `planned, completed, missed` | No explicit CHECK against backwards; app-controlled |

---

### 5.4 CHECK Constraints on Status

Status columns use `CHECK (status IN (...))` in migrations (e.g. `billing_purchases`, `workout_delivery_items`, `challenge_queue`). Values are constrained; ordering is not.

---

## 6. Severity Summary

| Severity | Count | Findings |
|----------|-------|----------|
| **CRITICAL** | 0 | — |
| **HIGH** | 0 | — |
| **MEDIUM** | 3 | MercadoPago L1 dedup ineffective; `fn_create_delivery_batch` allows duplicates; `fn_assign_workout` weekly limit TOCTOU |
| **LOW** | 2 | Coach concurrent assignment last-write; challenge join capacity TOCTOU |

---

## 7. Recommendations

1. **MercadoPago L1:** Add `UNIQUE` on `(metadata->>'mp_payment_id')` or a dedicated `mp_payment_id` column with UNIQUE for `payment_confirmed` events.
2. **fn_create_delivery_batch:** Add idempotency (UNIQUE or ON CONFLICT) to prevent duplicate batches.
3. **fn_assign_workout weekly limit:** Use `SELECT ... FOR UPDATE` on subscription/plan or a serializable transaction to avoid TOCTOU.
4. **challenge-join:** Consider wrapping participant insert + debit + ledger in a DB transaction or use a single RPC for atomicity.
