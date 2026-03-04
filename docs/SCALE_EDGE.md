# Scale Analysis: Supabase Edge Functions (Deno)

**Target:** 10,000 groups · 800K athletes · 30K staff  
**Date:** 2026-03-04  
**Platform:** Supabase Edge Functions (Deno Deploy isolates)  
**Timeout:** 60 seconds per invocation  
**Concurrency:** Regional, multi-isolate (Supabase manages pool)

---

## 1. Edge Function Inventory

| # | Function | Trigger | Purpose | Imports | Critical Path? |
|---|----------|---------|---------|---------|----------------|
| 1 | `auto-topup-cron` | pg_cron (hourly) | Loop ALL groups with auto-topup enabled, delegate to `auto-topup-check` | 5 (std, supabase, shared×3) | Billing |
| 2 | `auto-topup-check` | Internal (from cron) | Check single group balance, trigger Stripe charge if below threshold | 6 (std, supabase, shared×3, **Stripe**) | Billing |
| 3 | `lifecycle-cron` | pg_cron (every 5 min) | Championship transitions, challenge settlement, push notifications | 6 (std, supabase, shared×4) | **Core gameplay** |
| 4 | `strava-webhook` | External webhook | Ingest Strava activities: fetch, anti-cheat, store session, link challenges | 4 (std, supabase, shared×2) | **Data pipeline** |
| 5 | `strava-register-webhook` | Manual/one-time | Register Strava push subscription | 2 (std, shared×1) | Setup only |
| 6 | `settle-challenge` | User/cron | Compute challenge results, distribute wallet rewards | 8 (std, shared×7) | **Financial** |
| 7 | `compute-leaderboard` | User/cron | Materialize leaderboard snapshots (global/assessoria/championship) | 8 (std, shared×7) | Engagement |
| 8 | `send-push` | Internal | Send FCM push notifications to device tokens | 5 (std, supabase, shared×3) | Notifications |
| 9 | `notify-rules` | Internal/cron | Evaluate 15+ notification rules, dispatch via `send-push` | 6 (std, supabase, shared×4) | Notifications |
| 10 | `league-snapshot` | Weekly (from cron) | Calculate weekly league scores for all enrolled assessorias | 5 (std, supabase, shared×3) | Engagement |
| 11 | `trainingpeaks-sync` | User action | Push/pull workouts to/from TrainingPeaks API | 6 (std, supabase, shared×4) | Integration (frozen) |
| 12 | `trainingpeaks-oauth` | User action | OAuth flow for TrainingPeaks | 6 (std, supabase, shared×4) | Integration (frozen) |
| 13 | `evaluate-badges` | User/internal | Evaluate badge criteria, credit XP/coins | 8 (std, shared×7) | Gamification |
| 14 | `challenge-join` | User action | Join/accept a challenge, debit entry fee | 8 (std, shared×7) | Core gameplay |
| 15 | `challenge-invite-group` | User action | Invite assessoria to team challenge | 8 (std, shared×7) | Core gameplay |
| 16 | `champ-invite` | User action | Invite group to championship | 8 (std, shared×7) | Core gameplay |
| 17 | `create-checkout-mercadopago` | User action | Create MercadoPago checkout session | 8 (std, shared×7) | **Billing** |
| 18 | `delete-account` | User action | Soft-delete + hard-delete user account | 5 (std, shared×4) | Compliance |
| 19 | `webhook-mercadopago` | External webhook | Process MercadoPago payment notifications | 4 (std, supabase, shared×2) | **Billing** |
| 20 | `webhook-payments` | External webhook | Process Stripe webhook events | 5 (std, supabase, shared×2, **Stripe**) | **Billing** |
| 21 | `validate-social-login` | User action | TikTok OAuth (not yet configured) | 4 (std, shared×3) | Auth (future) |
| 22 | `clearing-cron` | pg_cron (daily) | Aggregate challenge prizes into clearing cases, settle custody | 5 (std, supabase, shared×3) | **Financial** |
| 23 | `reconcile-wallets-cron` | pg_cron (daily) | Reconcile all wallet balances vs ledger | 5 (std, supabase, shared×3) | **Financial** |
| 24 | `matchmake` | User action | Queue-based 1v1 matchmaking | 8 (std, shared×7) | Core gameplay |
| 25 | `generate-wrapped` | User action | Generate retrospective running summary | 8 (std, shared×7) | Engagement |
| 26 | `generate-running-dna` | User action | Calculate 6-axis running profile | 6 (std, shared×5) | Engagement |
| 27 | `eval-verification-cron` | pg_cron (daily) | Batch re-evaluate athlete verification status | 5 (std, supabase, shared×3) | Anti-cheat |
| 28 | `eval-athlete-verification` | User action | Evaluate caller's verification status | 6 (std, shared×5) | Anti-cheat |
| 29 | `submit-analytics` | User action | Submit session analytics, compute baselines/trends/insights | 7 (std, shared×6) | Coach analytics |
| 30 | `challenge-create` | User action | Create a new challenge | ~8 | Core gameplay |
| 31 | `challenge-get` | User action | Get challenge details | ~8 | Core gameplay |
| 32 | `challenge-list-mine` | User action | List user's challenges | ~8 | Core gameplay |
| 33 | `challenge-accept-group-invite` | User action | Accept team challenge invite | ~8 | Core gameplay |
| 34 | `champ-create` | User action | Create championship | ~8 | Core gameplay |
| 35 | `champ-enroll` | User action | Enroll in championship | ~8 | Core gameplay |
| 36 | `champ-accept-invite` | User action | Accept championship invite | ~8 | Core gameplay |
| 37 | `champ-cancel` | User action | Cancel championship | ~8 | Core gameplay |
| 38 | `champ-open` | User action | Open championship for enrollment | ~8 | Core gameplay |
| 39 | `champ-list` | User action | List championships | ~8 | Core gameplay |
| 40 | `champ-participant-list` | User action | List championship participants | ~8 | Core gameplay |
| 41 | `champ-lifecycle` | Internal | Championship lifecycle transitions | ~8 | Core gameplay |
| 42 | `champ-activate-badge` | User action | Activate championship badge | ~8 | Gamification |
| 43 | `champ-update-progress` | User action | Update championship progress | ~8 | Core gameplay |
| 44 | `create-checkout-session` | User action | Create Stripe checkout session | ~6 | Billing |
| 45 | `create-portal-session` | User action | Create Stripe customer portal session | ~6 | Billing |
| 46 | `list-purchases` | User action | List billing purchases | ~8 | Billing |
| 47 | `process-refund` | Staff action | Process a billing refund | ~6 | Billing |
| 48 | `token-create-intent` | User action | Create token purchase intent | ~8 | Financial |
| 49 | `token-consume-intent` | User action | Consume token intent | ~8 | Financial |
| 50 | `set-user-role` | Staff action | Set user role | ~6 | Admin |
| 51 | `complete-social-profile` | User action | Complete social profile after OAuth | ~6 | Auth |
| 52 | `verify-session` | User action | Verify a running session | ~6 | Anti-cheat |
| 53 | `calculate-progression` | User action | Calculate user progression/leveling | ~6 | Gamification |
| 54 | `clearing-confirm-sent` | Staff action | Confirm clearing case sent | ~6 | Financial |
| 55 | `clearing-confirm-received` | Staff action | Confirm clearing case received | ~6 | Financial |
| 56 | `clearing-open-dispute` | Staff action | Open clearing dispute | ~6 | Financial |
| 57 | `league-list` | User action | List league standings | ~8 | Engagement |

**Total: 57 edge functions** (7 crons, 4 external webhooks, 46 user/internal-triggered)

---

## 2. Concurrency Analysis

### Request Volume Estimates

| Source | Volume | Peak RPS | Functions Hit |
|--------|--------|----------|---------------|
| Strava webhooks | ~200K/day | ~5-10 RPS (sustained), 50+ RPS (burst after popular race) | `strava-webhook` |
| User-initiated actions | ~50K/day | ~2-5 RPS (sustained), 20+ RPS (evening peak) | Various user functions |
| MercadoPago webhooks | ~500/day | <1 RPS | `webhook-mercadopago` |
| Stripe webhooks | ~200/day | <1 RPS | `webhook-payments` |
| `lifecycle-cron` (5min) | 288/day | 1 per 5min, but each invocation fans out | `settle-challenge`, `league-snapshot`, `notify-rules` |
| `auto-topup-cron` (hourly) | 24/day | 1/hour, fans out to N groups | `auto-topup-check` |
| `notify-rules` fan-out | ~500-2000/day | Bursty via cron | `send-push` |

### Concurrency Bottlenecks

**CRITICAL — `strava-webhook`:** At 200K calls/day with burst potential of 50+ RPS after a major race event (e.g., Sunday morning mass start), this is the highest-volume function. Each invocation makes:
- 1 DB lookup (`strava_connections`)
- 1 duplicate check (`sessions`)
- 0-1 Strava token refresh (external API, up to 15s)
- 1 Strava activity fetch (external API, up to 15s)
- 1 Strava streams fetch (external API, up to 15s)
- 1 Storage upload
- 1 session insert
- 1 challenge linkage (N queries for N active challenges)
- 3 fire-and-forget RPCs (`eval_athlete_verification`, `recalculate_profile_progress`, `evaluate_badges_retroactive`)
- 1 park detection (loads ALL parks into memory)

**At 50 concurrent invocations:** Each creates its own Supabase client (new HTTP connection to PostgREST). 50 concurrent webhooks = 50 PostgREST connections + 50-150 Strava API calls.

**CRITICAL — `notify-rules`:** This 1,229-line monolith evaluates up to 15 rules. When called with no specific rule (evaluate all), it runs sequentially through all rules, each making multiple DB queries. A single invocation touching `streak_at_risk` or `inactivity_nudge` loads large user sets into memory.

### Connection Model

Every function creates a **new `createClient()` per request**. Supabase JS client v2 uses HTTP (PostgREST), not direct Postgres connections. This is safe from connection pool exhaustion but has these implications:

- Each request adds HTTP overhead to PostgREST
- PostgREST has its own connection pool to Postgres (default 100 connections on Supabase Pro)
- `requireUser()` in `_shared/auth.ts` creates **3 Supabase clients per call** (lines 60-93): `verifyClient`, `db` (user-scoped), and `adminDb` (service-role)

---

## 3. Cold Start Analysis

### Import Weight by Function Category

| Category | Imports | Cold Start Risk | Affected Functions |
|----------|---------|-----------------|-------------------|
| Stripe SDK (`esm.sh/stripe@14`) | Heavy (~500KB) | **HIGH** — 800ms-2s | `auto-topup-check`, `webhook-payments` |
| Standard shared (auth, cors, http, obs, validate, errors, rate_limit) | Medium (~50KB total) | LOW — <200ms | All 46 user-initiated functions |
| Minimal (std + shared×2) | Light (~20KB) | LOW — <100ms | `strava-webhook`, `strava-register-webhook`, webhooks |
| Logger extra (`_shared/logger.ts`) | Light | LOW | `notify-rules`, `compute-leaderboard` |

### Specific Cold Start Risks

1. **`auto-topup-check`** (line 6): Imports `Stripe from "https://esm.sh/stripe@14?target=deno"` — the Stripe SDK is large and adds 800ms+ to cold starts.

2. **`webhook-payments`** (line 5): Same Stripe import. At low webhook volume (<1 RPS), this function will cold-start frequently.

3. **`trainingpeaks-sync`** (lines 10-11): Initializes `SUPABASE_URL` and `SERVICE_KEY` at **module scope** (outside `serve()`), creating a Supabase client on every cold start even if the feature flag will reject the request.

4. **`trainingpeaks-oauth`** (lines 9-16): Same module-scope initialization of 7 env vars.

5. **`requireUser()` in `_shared/auth.ts`**: Creates 3 Supabase clients per authentication call. For the 46 user-initiated functions, every request pays this cost.

### Mitigation Status

- All functions use `https://deno.land/std@0.177.0/http/server.ts` — pinned version, good for caching.
- ESM imports from `esm.sh` are cached by Deno Deploy's module cache.
- No function pre-warms connections or caches.

---

## 4. Timeout Risk Matrix

| Risk | Function | Why | Est. Duration at Scale | Limit |
|------|----------|-----|----------------------|-------|
| **CRITICAL** | `auto-topup-cron` | Serial loop over ALL enabled groups with 200ms delay each. At 2,000 enabled groups: 2,000 × (fetch 15s max + 200ms delay) | **400s+ (7 min)** | 60s |
| **CRITICAL** | `lifecycle-cron` | Fetches open/active championships, then loops participants serially updating ranks. Also calls `settle-challenge` (15s timeout each) for up to 50 challenges + `league-snapshot` + 3× `notify-rules` | **120s+ (fans out)** | 60s |
| **CRITICAL** | `league-snapshot` | Loops ALL enrolled groups (up to 10,000). For each: fetch members, fetch sessions, fetch challenge wins — 4 sequential DB queries per group | **600s+ at 10K groups** | 60s |
| **CRITICAL** | `compute-leaderboard` (batch_assessoria) | Loops ALL coaching groups serially, calling `compute_leaderboard_assessoria` RPC for each. At 10K groups with 100ms/RPC | **1,000s (16 min)** | 60s |
| **HIGH** | `settle-challenge` | Per challenge: fetch participants, fetch verification status, compute results, N parallel `increment_wallet_balance` RPCs. With 100 participants: ~100 wallet ops | **30-50s per challenge** | 60s |
| **HIGH** | `notify-rules` (evaluate all) | 15 rules evaluated sequentially. `streak_at_risk` queries `v_user_progression` for ALL users with streak≥3, then checks sessions. `inactivity_nudge` scans ALL sessions in 30 days | **45-90s with 800K users** | 60s |
| **HIGH** | `clearing-cron` | Fetches ALL `challenge_prize_pending` ledger entries, ALL `clearing_case_items` for anti-join, then loops creating cases | **30-60s at scale** | 60s |
| **HIGH** | `strava-webhook` | 3 sequential Strava API calls (15s timeout each) + `detectAndLinkPark` loads ALL parks table. Worst case: token refresh + activity + streams + storage + insert + challenge link | **45-55s** | 60s |
| **MEDIUM** | `eval-verification-cron` | Capped at BATCH_SIZE=100. 100 serial `eval_athlete_verification` RPCs | **20-40s** | 60s |
| **MEDIUM** | `send-push` | Serial loop over device tokens calling FCM. With 1000 tokens for a group notification | **15-30s** | 60s |
| **MEDIUM** | `generate-wrapped` | Fetches full session history for a period + challenge results + badges + profile | **5-15s** | 60s |
| **LOW** | `submit-analytics` | 5 parallel DB fetches + baseline/trend computation + insight generation. Bounded by group size (200 members max) | **3-10s** | 60s |
| **LOW** | User CRUD functions | Simple auth + 2-5 DB operations | **1-5s** | 60s |

### Worst-Case Timeout Chains

```
lifecycle-cron (60s)
 ├─ settle-challenge ×50 (15s timeout each, serial)  → 750s total attempted
 │   └─ increment_wallet_balance ×N (parallel per challenge)
 ├─ league-snapshot ×1 (15s timeout)
 │   └─ notify-rules per group with rank change (15s timeout each)
 └─ notify-rules ×3 (15s timeout each)
     └─ send-push ×N (15s timeout each)
```

**`lifecycle-cron` will timeout after 60s having processed only ~3-4 challenges out of potentially hundreds.**

---

## 5. Memory Pressure Points

| Function | Memory Pattern | Risk at Scale |
|----------|---------------|---------------|
| `strava-webhook` | Loads GPS streams (latlng, time, heartrate, velocity, altitude, cadence) into memory. A 2-hour run with 1Hz sampling = ~7,200 points × 6 streams. Also loads ALL `parks` table for detection. | **HIGH** — ~5-20MB per invocation. 50 concurrent = 250MB-1GB |
| `notify-rules` (inactivity_nudge) | Fetches ALL sessions in last 30 days for ALL users (`start_time_ms` ≥ thirtyDaysAgoMs). At 800K users with avg 8 sessions/month = ~6.4M rows | **CRITICAL** — Unbounded query, will OOM or timeout |
| `notify-rules` (streak_at_risk) | Queries `v_user_progression` for ALL users with streak≥3. Could be 100K+ rows | **HIGH** — Unbounded result set |
| `league-snapshot` | Accumulates `groupScores[]` for all 10K groups, plus `cumulativeMap` and `prevSnapshots` for all groups | **MEDIUM** — ~5MB for 10K groups |
| `compute-leaderboard` (batch) | Loops 10K groups but processes in chunks of 100. Memory is bounded per chunk | **LOW** — properly chunked |
| `clearing-cron` | Fetches ALL `coin_ledger` entries with `reason=challenge_prize_pending` and ALL `clearing_case_items` for set comparison | **HIGH** — Unbounded queries grow with platform age |
| `evaluate-badges` | Loads ALL badges catalog + 9 parallel queries. Badge catalog is small (<100 rows) | **LOW** |
| `submit-analytics` | 5 parallel fetches bounded by group size (200 member limit) and 14-day window | **LOW** — well bounded |
| `settle-challenge` | Loads all participants + verification + ledger entries per challenge. Most challenges have 2-50 participants | **LOW** |

### Memory Limits

Supabase Edge Functions (Deno Deploy) have a **memory limit of 150MB per isolate** (shared across concurrent requests in the same isolate). The `strava-webhook` and `notify-rules` functions are the primary risk vectors.

---

## 6. Cascading Failure Scenarios

### Scenario 1: Strava API Outage

```
Strava API down/slow (>15s responses)
 └─ strava-webhook: AbortController fires at 15s per call
     ├─ Token refresh fails → returns { ignored: true, reason: "token_refresh_failed" }
     ├─ Activity fetch fails → returns { ignored: true, reason: "activity_fetch_failed" }
     └─ Impact: 200K activities/day NOT imported
         ├─ Challenge progress not updated (users see stale data)
         ├─ Badges not evaluated
         ├─ Park activities not recorded
         └─ Profile progression stale
```

**Blast radius:** All Strava-connected users (potentially 80%+ of 800K athletes). No retry mechanism — events are lost permanently.

### Scenario 2: FCM Outage

```
FCM API slow/down
 └─ send-push: 15s timeout per token, serial loop
     └─ All callers of send-push timeout:
         ├─ notify-rules hangs → lifecycle-cron hangs
         ├─ settle-challenge fire-and-forget leaks
         ├─ evaluate-badges fire-and-forget leaks
         └─ Impact: Push notifications silently fail, BUT:
             ├─ lifecycle-cron may not finish challenge settlement
             └─ Challenge results delayed
```

**Blast radius:** Notifications only, BUT `lifecycle-cron` has a 60s budget and wastes time waiting for `notify-rules` → `send-push` chain.

### Scenario 3: Database Overload

```
PostgREST/Postgres saturated (connection pool exhausted)
 └─ ALL functions fail simultaneously:
     ├─ User actions: 5xx errors across the app
     ├─ Webhook processing stops (Strava, payments)
     ├─ Cron jobs fail → challenges not settled, leagues not scored
     ├─ Payment webhooks fail → purchases stuck in "pending"
     └─ Wallet reconciliation fails → potential drift accumulates
```

**Blast radius:** Total platform outage. Every function creates new DB clients per request.

### Scenario 4: `settle-challenge` Partial Failure

```
settle-challenge processes 5 of 50 challenges, then times out
 └─ 5 challenges: status="completed", results written, wallets credited
 └─ 45 challenges: status still "active" or "completing"
     ├─ Next lifecycle-cron run: retries, but may timeout again
     ├─ Users see inconsistent states
     └─ If wallet credits were partially applied:
         └─ Pool math wrong on next attempt (double-count risk)
         NOTE: "completing" status + existingResults guard (line 170) prevents this
```

**Mitigation present:** The `completing` status lock (line 152-161) and existing results check (line 166-174) prevent double-writes. However, repeated timeouts mean challenges stay unsettled indefinitely.

### Scenario 5: `auto-topup-cron` Timeout Storm

```
auto-topup-cron starts, loops 2000 groups with 200ms delay
 └─ After 60s: processed ~50-80 groups (15s timeout per fetch + 200ms delay)
 └─ Remaining 1920 groups: NOT checked
     ├─ Groups run out of credits without auto-top-up
     ├─ Coaches can't assign workouts (token debit fails)
     └─ Revenue loss from missed automatic charges
```

**Blast radius:** Revenue-impacting. Groups that sort later alphabetically/by-ID never get checked.

---

## 7. External API Rate Limits

| External API | Rate Limit | Current Usage Pattern | Risk at Scale |
|-------------|------------|----------------------|---------------|
| **Strava API** | 100 requests/15min per app, 1000/day per app (read) | `strava-webhook`: 2-3 calls per event (activity + streams + optional refresh) | **CRITICAL** — 200K events/day × 2-3 calls = 400-600K calls/day. Daily limit is 1000 for reads. **Will be rate-limited.** |
| **FCM HTTP v1** | 500K messages/day, 1000 msgs/sec | `send-push`: 1 FCM call per device token | **LOW** — 800K athletes × avg 1.5 devices, but only ~10-50K pushes/day |
| **Stripe API** | 100 reads/sec, 100 writes/sec | `auto-topup-check`: 1 PaymentIntent.create per trigger. `webhook-payments`: 1-2 reads per event | **LOW** — <500 Stripe calls/day |
| **MercadoPago API** | 100 req/sec (undocumented soft limit) | `create-checkout-mercadopago`: 1 preference create. `webhook-mercadopago`: 1 payment fetch | **LOW** — <500 MP calls/day |
| **TrainingPeaks API** | 60 req/min per user token | `trainingpeaks-sync`: N workouts per athlete. Feature-flagged OFF | **LOW** — frozen behind feature flag |

### CRITICAL: Strava Rate Limit Breach

The Strava API v3 has **application-level rate limits** (not per-user):
- **Short-term:** 100 requests per 15 minutes (600/hour)
- **Daily:** 1,000 requests per day (for read endpoints)

At 200K webhook events/day, even if only 50% are `activity.create` for runs, that's 100K events requiring 2-3 Strava API calls each = **200-300K API calls/day** — **300× over the daily limit**.

**Current code has no rate-limit awareness** — `strava-webhook` (lines 181-217) makes Strava API calls immediately upon receiving each webhook, with no queuing, batching, or backoff.

---

## 8. Connection Pool Exhaustion Risk

### PostgREST → Postgres Pool

Supabase PostgREST default pool: **100 connections** (Pro plan). Each Edge Function HTTP call to PostgREST uses one pool connection for its duration.

| Scenario | Concurrent DB Operations | Pool Pressure |
|----------|------------------------|---------------|
| Normal load (5 RPS user + 5 RPS Strava) | ~30-50 concurrent PostgREST queries | **50% pool** |
| Strava burst (50 RPS after race) | ~150-250 concurrent queries (3-5 per webhook) | **150-250%** ⚠️ |
| lifecycle-cron + user traffic | Cron fans out to settle-challenge, league-snapshot, notify-rules (each making many queries) + normal user traffic | **120-200%** ⚠️ |
| All crons overlap (worst case) | auto-topup-cron + lifecycle-cron + clearing-cron + eval-verification-cron running simultaneously | **200-300%** ⚠️ |

### Per-Request Client Creation

The `requireUser()` auth helper (`_shared/auth.ts` lines 60-93) creates **3 separate Supabase clients** per authenticated request:

```
verifyClient (line 60) — for auth.getUser()
db (line 77) — user-scoped (RLS)
adminDb (line 86) — service-role (bypass RLS)
```

Each client maintains its own HTTP connection state. For 46 user-initiated functions, every request creates 3 clients. At 50 concurrent user requests, that's 150 logical client instances.

### Supabase Storage

`strava-webhook` (line 359-364) uploads GPS points to Supabase Storage. At 200K sessions/day, this is ~200K storage writes/day. Supabase Storage uses its own connection pool and has separate rate limits.

---

## 9. Recommendations (Prioritized)

### P0 — CRITICAL (will break at scale, revenue/data impact)

#### R1: Replace `auto-topup-cron` serial loop with database-driven queue
**Impact:** Prevents 60s timeout with 2000+ groups  
**Current:** `auto-topup-cron/index.ts` lines 91-124 — serial `for` loop with 200ms delay per group  
**Fix:** Use pg_cron to call a Postgres function that inserts groups into a work queue table, then have `auto-topup-check` pull from the queue. Alternatively, use `pg_net` to fan out directly from Postgres without the orchestrator function.

#### R2: Rewrite `lifecycle-cron` as a fan-out dispatcher
**Impact:** Prevents 60s timeout, ensures all challenges/championships get processed  
**Current:** `lifecycle-cron/index.ts` lines 86-167 — serial loops over championships and challenges, then serial calls to 4 other edge functions  
**Fix:** Split into phases:
1. A lightweight cron that queries due items and inserts them into a `lifecycle_queue` table
2. Individual workers that process one item at a time (triggered by pg_net or a separate cron)
3. Limit to 50 challenges per cron run (already present at line 144) but add cursor-based pagination

#### R3: Implement Strava webhook queue + rate-limit throttle
**Impact:** Prevents Strava API rate limit breach (currently 300× over daily limit)  
**Current:** `strava-webhook/index.ts` — processes each webhook synchronously, making 2-3 Strava API calls immediately  
**Fix:**
1. `strava-webhook` should only validate the event and insert it into a `strava_event_queue` table (sub-1s response)
2. A separate `strava-process-event` function (triggered by pg_cron every 10s) dequeues events respecting Strava's 100 req/15min limit
3. Implement token bucket rate limiting: max 6 API calls/second (90/15min leaving 10% headroom)

#### R4: Rewrite `league-snapshot` to use database aggregation
**Impact:** Prevents 60s timeout with 10K groups  
**Current:** `league-snapshot/index.ts` lines 177-244 — loops ALL enrolled groups, making 4 sequential DB queries per group  
**Fix:** Replace the per-group loop with a single SQL query/RPC that computes scores using `GROUP BY`. The formula (line 231-232) is simple arithmetic that Postgres can compute in a single aggregate query joining `coaching_members`, `sessions`, and `challenge_results`.

#### R5: Fix `notify-rules` unbounded queries
**Impact:** Prevents OOM and timeout with 800K users  
**Current:**
- `inactivity_nudge` (line 893-897): `SELECT user_id FROM sessions WHERE start_time_ms >= thirtyDaysAgoMs` — returns up to 6.4M rows
- `streak_at_risk` (line 277): `SELECT * FROM v_user_progression WHERE streak_current >= 3` — returns 100K+ rows  
**Fix:**
1. Move evaluation logic into Postgres functions that operate on the data in-place
2. Use `LIMIT` + cursor/pagination for any unbounded query
3. Cap each rule to process max 500 users per invocation

### P1 — HIGH (degraded experience, partial failures)

#### R6: Add retry mechanism for `strava-webhook` data loss
**Impact:** Recovers lost activities when Strava API is slow/down  
**Current:** If any Strava API call fails, the webhook returns `{ ignored: true }` and the activity is permanently lost  
**Fix:** Insert failed events into a `strava_failed_events` table. Add a daily cron that retries failed events.

#### R7: Batch `send-push` FCM calls
**Impact:** Prevents notification function timeouts  
**Current:** `send-push/index.ts` lines 144-203 — serial loop over device tokens, one FCM call per token  
**Fix:** Use FCM batch send API (up to 500 messages per request) instead of individual calls. Group tokens into batches of 500.

#### R8: Fix `settle-challenge` N+1 wallet operations
**Impact:** Reduces per-challenge settlement time from 30-50s to 5-10s  
**Current:** `settle-challenge/index.ts` lines 529-538 — `Promise.all()` of N individual `increment_wallet_balance` RPCs  
**Fix:** Create a batch RPC `increment_wallet_balances_batch(p_entries jsonb)` that applies all wallet changes in a single transaction.

#### R9: Remove module-scope initialization in `trainingpeaks-*`
**Impact:** Eliminates unnecessary DB call on cold start  
**Current:** `trainingpeaks-sync/index.ts` lines 10-11 and `trainingpeaks-oauth/index.ts` lines 9-16 initialize env vars and create clients at module scope  
**Fix:** Move all initialization inside the `serve()` handler.

#### R10: Cap `clearing-cron` unbounded queries
**Impact:** Prevents timeout as platform ages  
**Current:** `clearing-cron/index.ts` lines 121-125 — fetches ALL `challenge_prize_pending` ledger entries without LIMIT, and line 139 fetches ALL `clearing_case_items`  
**Fix:** Add `.limit(1000)` and process in batches. Use a processed flag or timestamp cursor.

#### R11: Eliminate full `parks` table scan in `strava-webhook`
**Impact:** Reduces per-webhook memory and latency  
**Current:** `strava-webhook/index.ts` line 621 — `SELECT id, center_lat, center_lng, radius_m FROM parks` (loads entire table)  
**Fix:** Use PostGIS `ST_DWithin()` with a spatial index to find nearby parks. Or cache the parks list in a module-scope variable (refreshed every 5 minutes) since the parks table changes rarely.

### P2 — MEDIUM (optimization, reliability)

#### R12: Reduce `requireUser()` client overhead
**Impact:** Reduces auth latency by ~30%  
**Current:** `_shared/auth.ts` creates 3 Supabase clients per auth call  
**Fix:** Only create `adminDb` when needed (lazy initialization). Most functions don't use `adminDb`. Return a getter function instead of eagerly creating it.

#### R13: Add health check bypass before auth in frozen functions
**Impact:** Prevents unnecessary DB calls for health probes  
**Current:** `trainingpeaks-sync` line 82 creates a DB client to check the feature flag even for health checks. The health check at line 77 runs before the flag check.  
**Fix:** Already handled correctly (health check returns before flag check). No change needed.

#### R14: Add `compute-leaderboard` batch timeout guard
**Impact:** Prevents incomplete batch processing  
**Current:** `compute-leaderboard/index.ts` lines 262-295 — loops all groups with no elapsed-time check  
**Fix:** Add `if (elapsed() > 50_000) break;` after each batch to ensure the function returns before the 60s timeout with partial results. Store progress cursor for next invocation.

#### R15: Implement graceful degradation for `lifecycle-cron`
**Impact:** Ensures highest-priority work completes first  
**Current:** `lifecycle-cron` processes in fixed order: champ activate → champ complete → challenge settle → challenge expire → league snapshot → 3× notify-rules  
**Fix:** Add elapsed-time checks between phases. If >40s elapsed, skip lower-priority phases (notifications). Log skipped work for the next cron cycle.

#### R16: Add idempotency key to `strava-webhook` park detection
**Impact:** Prevents duplicate `park_activities` entries  
**Current:** `strava-webhook/index.ts` line 639 — `INSERT INTO park_activities` has no dedup check  
**Fix:** Add a unique constraint on `(session_id, park_id)` or check before insert.

### P3 — LOW (future-proofing)

#### R17: Monitor and alert on function duration percentiles
Set up alerts for p95 > 30s on: `lifecycle-cron`, `settle-challenge`, `notify-rules`, `strava-webhook`, `league-snapshot`.

#### R18: Consider splitting `notify-rules` into individual rule functions
The 1,229-line monolith evaluates 15 rules. Split each rule into its own function for independent scaling and timeout isolation.

#### R19: Add circuit breakers for external API calls
Wrap Strava, FCM, Stripe, and MercadoPago calls with circuit breaker logic: if >5 failures in 1 minute, stop calling for 5 minutes.

#### R20: Pre-warm critical functions
Use a lightweight cron (every 5 min) that hits `/health` on `strava-webhook`, `settle-challenge`, and `webhook-payments` to keep isolates warm and avoid cold starts on critical paths.

---

## Summary: Risk Heat Map

```
                        Low Volume    Med Volume    High Volume
                        (<1 RPS)      (1-10 RPS)    (10+ RPS)
                    ┌─────────────┬─────────────┬─────────────┐
  Low Complexity    │ strava-reg  │ challenge-  │             │
  (<5 DB ops)       │ validate-   │  get/list   │             │
                    │  social     │ champ-list  │             │
                    ├─────────────┼─────────────┼─────────────┤
  Med Complexity    │ webhook-mp  │ challenge-  │             │
  (5-15 DB ops)     │ webhook-pay │  join       │             │
                    │ delete-acct │ matchmake   │             │
                    │ checkout-mp │ eval-badge  │             │
                    ├─────────────┼─────────────┼─────────────┤
  High Complexity   │ clearing-   │ settle-     │ ⚠️ strava-  │
  (15+ DB ops,      │  cron       │  challenge  │  webhook    │
   loops,           │ league-     │ notify-     │             │
   external APIs)   │  snapshot   │  rules      │             │
                    │ auto-topup  │ lifecycle-  │             │
                    │  cron       │  cron       │             │
                    └─────────────┴─────────────┴─────────────┘
                              ▲ DANGER ZONE ▲
```

**Top 5 functions that will break first at scale:**

1. **`strava-webhook`** — Strava API rate limits will be hit at ~3% of target volume
2. **`auto-topup-cron`** — Will timeout at ~300 enabled groups (3% of 10K)
3. **`league-snapshot`** — Will timeout at ~50 enrolled groups (0.5% of 10K)
4. **`lifecycle-cron`** — Will timeout when >4 challenges need settling simultaneously
5. **`notify-rules`** (inactivity_nudge/streak_at_risk) — Will OOM/timeout at ~50K users (6% of 800K)
