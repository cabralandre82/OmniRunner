# Chaos de Performance — Chaos Testing Report

**Date:** 2026-03-04  
**Scope:** N+1 queries, unbounded queries, heavy computation, missing indexes, payload size, edge function cold start  
**Repository:** /home/usuario/project-running

---

## 1. N+1 QUERIES

### 1.1 Edge Functions — CRITICAL

| File | Location | Pattern | Impact | Severity |
|------|----------|---------|--------|----------|
| `trainingpeaks-sync/index.ts` | Push action, lines 163-234 | `for (const sync of pendingSyncs) { await db.from(...).update(...); await fetch(TP_API); }` | 50 syncs = 50 sequential DB updates + 50 TP API calls. Total ~100+ round-trips. | **CRITICAL** |
| `trainingpeaks-sync/index.ts` | Pull action, lines 250-280 | `for (const link of links) { await fetch(TP_API); for (const tw of tpWorkouts) { await db.rpc("fn_import_execution"...) } }` | Per athlete: 1 API call + N RPCs per workout. Nested loop. | **MAJOR** |
| `settle-challenge/index.ts` | Lines 395-402, 517-525 | `await Promise.all(ledgerEntries.map((entry) => db.rpc("increment_wallet_balance", {...})))` | Parallel RPCs per ledger entry — not strictly N+1 but N concurrent DB calls. With 20 participants = 20+ RPCs. | **MINOR** |

**trainingpeaks-sync push detail:**
- Per sync item: 1× `coaching_tp_sync` UPDATE, 1× `fetch(TP_API)` (POST workout).
- Pre-fetch batching exists for `deviceLinks`, `assignments`, `templates`, `blocks` — good.
- The loop itself still does 2 awaits per item. With 50 items: 100 sequential operations.

### 1.2 Portal — N+1

| File | Location | Pattern | Impact | Severity |
|------|----------|---------|--------|----------|
| `portal/src/app/platform/support/page.tsx` | Lines 36-52 | `for (const t of rawTickets) { await supabase.from("coaching_groups").select(...); await supabase.from("support_messages").select(..., { count: "exact", head: true }); }` | 2 queries per ticket. 100 tickets = 200 extra queries. | **MAJOR** |

### 1.3 Flutter — No N+1 in Presentation

- Screens delegate to services/repos. Batched patterns (e.g., `today_data_service` uses `inFilter` for challenges/championships).
- No `for ... await db` in presentation layer.

---

## 2. UNBOUNDED QUERIES

### 2.1 Flutter

| File | Query | Limit | Risk |
|------|-------|-------|------|
| `workout_delivery_service.dart` | `listPublishedItems` | None | Athlete could have hundreds of published items | **MINOR** |
| `workout_delivery_service.dart` | `countPublishedItems` | None | Uses `select('id')` — returns all IDs, then `.length` | **MAJOR** — should use count RPC or `count: 'exact'` |
| `staff_disputes_screen.dart` | `clearing_cases` with `or(...)` | None | Could return many rows | **MAJOR** |
| `staff_credits_screen.dart` | `coaching_token_inventory` | None | Single group, likely small | **MINOR** |
| `staff_credits_screen.dart` | `institution_credit_purchases` | None | Same | **MINOR** |
| `staff_championship_manage_screen.dart` | `championships.select()` | None | Single row by id | OK |
| `staff_championship_manage_screen.dart` | `coaching_groups` for invite modal | None | Could be many groups | **MINOR** |

### 2.2 Portal

| File | Query | Limit | Risk |
|------|-------|-------|------|
| `portal/src/app/platform/support/page.tsx` | `support_tickets` | None | All tickets in DB | **MAJOR** |
| `portal/src/app/platform/conquistas/page.tsx` | `badges` | None | Platform catalog, finite | **MINOR** |
| `portal/src/app/platform/produtos/page.tsx` | `billing_products` | None | Platform catalog | **MINOR** |
| `portal/src/app/platform/fees/page.tsx` | `platform_fee_config` | None | Small config table | OK |
| `portal/src/app/(portal)/audit/page.tsx` | `clearing_events`, `clearing_settlements` | None | Per-group, could grow | **MAJOR** |
| `portal/src/app/(portal)/custody/page.tsx` | `coin_ledger` | None | `.select("delta_coins").eq("issuer_group_id", groupId)` — entire ledger for group | **CRITICAL** |
| `portal/src/app/(portal)/clearing/page.tsx` | settlements | limit(100) per side | OK |
| `portal/src/app/(portal)/custody/page.tsx` | deposits, withdrawals | limit(50) | OK |
| `portal/src/app/(portal)/delivery/page.tsx` | batches | limit(20), items limit(200) | OK |

### 2.3 Edge Functions

| File | Query | Limit | Risk |
|------|-------|-------|------|
| `settle-challenge/index.ts` | `challenges` | None when filtering by `ends_at_ms` | Bounded by active challenges; low volume | **MINOR** |
| `trainingpeaks-sync/index.ts` | `coaching_tp_sync` pending | limit(50) | OK |

---

## 3. HEAVY COMPUTATION

### 3.1 Edge Functions

| File | Location | Work | Impact |
|------|----------|------|--------|
| `settle-challenge/index.ts` | Lines 176-380 | Ranking, team score computation, result building | CPU-bound for large challenges (e.g., 50+ participants). Single-threaded Deno. | **MINOR** |
| `strava-webhook/index.ts` | Per-event processing | GPS validation, anti-cheat logic | Could hit timeout on complex activities. | **MINOR** (per AUDIT_INTEGRATIONS) |
| `generate-wrapped/index.ts` | Year-end stats | Aggregations across sessions | Likely heavy; depends on user history size. | **MINOR** |
| `compute-leaderboard/index.ts` | Leaderboard calc | Sorting, aggregation | Bounded by challenge size. | **MINOR** |

### 3.2 Flutter — Build/Compute

| File | Pattern | Risk |
|------|---------|------|
| `today_screen.dart` | Data load in initState; build uses `body: _loading ? ...` | No heavy compute in build |
| `run_details_screen.dart` | `_drawRoute()` after load | Map drawing — could be heavy for long routes |
| General | No observed heavy loops in `build()` | OK |

### 3.3 Portal

| File | Pattern | Risk |
|------|---------|------|
| `audit/page.tsx` | `for (const s of settlements) { settlementsByEvent.get/set }` | O(n) in-memory grouping; fine for hundreds |
| `custody/page.tsx` | `for (const w of withdrawals)` building ledger entries | Linear; acceptable |

---

## 4. MISSING INDEXES

### 4.1 Existing Indexes (from migrations)

- `20260305000000_workout_delivery.sql`: `idx_delivery_items_athlete` on `(athlete_user_id, status)` ✅
- `20260303700000_portal_performance_indexes.sql`: sessions, KPIs, alerts, attendance, announcement_reads, member_status ✅

### 4.2 Migration `20260306200000_missing_indexes.sql`

**Note:** The file at this path contains `reconcile_wallet`, `reconcile_all_wallets`, and `archive_old_sessions` — not index creation. The following are recommended based on query patterns observed in the audit:

| Table | Columns | Query Pattern | Recommended Index |
|-------|---------|---------------|-------------------|
| `billing_events` | `(purchase_id, event_type)` | Dedup checks in webhook | `idx_billing_events_purchase_type` |
| `billing_purchases` | `payment_reference` | Webhook refund lookup | `idx_billing_purchases_payment_ref` |
| `coin_ledger` | `(issuer_group_id)` | Custody page full ledger scan | `idx_coin_ledger_issuer_group` |
| `support_tickets` | `(group_id, updated_at)` | Support list per group | `idx_support_tickets_group_updated` |
| `clearing_settlements` | `(creditor_group_id, created_at)`, `(debtor_group_id, created_at)` | Clearing page | May already exist; verify |
| `coaching_tp_sync` | `sync_status` | trainingpeaks-sync pending | `idx_tp_sync_status` WHERE status='pending' |

### 4.3 Query Patterns Not Covered

| Query | Location | Index Needed |
|-------|----------|--------------|
| `coin_ledger` WHERE `issuer_group_id` | custody/page.tsx | Yes |
| `clearing_events` WHERE `redeemer_group_id` | audit/page.tsx | Yes |
| `support_tickets` ORDER BY `updated_at` | platform/support | Yes |

---

## 5. PAYLOAD SIZE

### 5.1 Over-fetching

| File | Query | Columns | Issue |
|------|-------|---------|-------|
| `workout_delivery_service.dart` | `listPublishedItems` | `.select()` (all) | Fetches `export_payload` (JSONB with blocks, notes) for each item. Can be large. | **MINOR** |
| `staff_credits_screen.dart` | `coaching_token_inventory`, `institution_credit_purchases` | `.select()` | All columns; likely few columns needed | **MINOR** |
| `supabase_wearable_repo.dart` | `coaching_device_links` | `.select()` | All columns including tokens | **MINOR** |
| `challenge-join/index.ts` | `challenges` | `.select("*")` | Full row | **MINOR** |
| `settle-challenge/index.ts` | `challenge_participants` | `.select("*")` | Full row | **MINOR** |

### 5.2 Explicit Column Selection (Good)

- Portal delivery page: explicit columns for batches and items ✅
- Portal custody: explicit columns for deposits, withdrawals ✅
- Most Flutter services: explicit columns in `select(...)` ✅

### 5.3 Images/Avatars

- `profile_data_service.dart` uploads to `avatars`; no evidence of resize. Full resolution stored. Download uses `getPublicUrl` — no thumbnail variant. | **MINOR**

---

## 6. EDGE FUNCTION COLD START

### 6.1 Client Creation

| Pattern | Usage |
|---------|-------|
| `createClient(supabaseUrl, serviceKey, {...})` | Every edge function creates client per request. Standard; no heavy init. |
| `requireUser(req)` | Creates client with JWT. Same. |

### 6.2 Heavy Object Initialization

- No global caches or heavy singletons in edge functions.
- Each request is stateless.
- Cold start cost: Deno runtime + import resolution. Not app-specific.

### 6.3 Recommendation

- Consider connection pooling if Supabase adds support.
- No critical cold-start issues identified.

---

## Summary — Critical/Major Findings

| ID | Finding | Severity |
|----|---------|----------|
| P1 | `trainingpeaks-sync` push: 50 syncs = 100+ sequential operations | **CRITICAL** |
| P2 | Portal custody: `coin_ledger` queried without limit — full group ledger | **CRITICAL** |
| P3 | Portal support: N+1 — 2 queries per ticket in loop | **MAJOR** |
| P4 | `workout_delivery_service.countPublishedItems` — fetches all IDs instead of count | **MAJOR** |
| P5 | Portal support_tickets, audit clearing_events/settlements — unbounded | **MAJOR** |
| P6 | Staff disputes clearing_cases — unbounded | **MAJOR** |
| P7 | `trainingpeaks-sync` pull: nested loop with RPC per workout | **MAJOR** |
| P8 | Missing indexes: `coin_ledger.issuer_group_id`, `billing_purchases.payment_reference` | **MAJOR** |

---

## Recommended Actions (Non-Modifying)

1. **trainingpeaks-sync push:** Batch updates and/or parallelize TP API calls with `Promise.all` (with concurrency cap).
2. **custody coin_ledger:** Add `.limit(N)` or use aggregate RPC; do not load full ledger for display.
3. **Portal support:** Batch group/message lookups (single query with `in`) or use joins.
4. **countPublishedItems:** Use Supabase `.select('id', { count: 'exact', head: true })` or dedicated count RPC.
5. **Unbounded queries:** Add `.limit(500)` or similar for list endpoints; paginate where needed.
6. **Indexes:** Create indexes on `coin_ledger(issuer_group_id)`, `billing_purchases(payment_reference)`, `support_tickets(group_id, updated_at)`.

---

*Report generated by Chaos Testing analysis. No files were modified.*
