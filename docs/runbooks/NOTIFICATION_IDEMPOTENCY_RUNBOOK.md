# Notification Idempotency Runbook

> **Audit ref:** L12-09 · **Owner:** coo · **Severity:** 🟠 High
> **Migration:** `supabase/migrations/20260421240000_l12_09_notification_idempotency.sql`
> **Integration tests:** `tools/test_l12_09_notification_idempotency.ts`
> **Related:** CRON_HEALTH_RUNBOOK.md · EDGE_RETRY_WRAPPER_RUNBOOK.md

---

## 1. Summary

`notify-rules` and `onboarding-nudge` used to dedup push notifications via a
non-atomic `SELECT` on `public.notification_log` followed by the push
dispatch and a post-hoc `INSERT`. Two concurrent invocations (cron tick +
operator trigger, or two overlapping 5-min crons) could both pass the
`wasRecentlyNotified` check and fire the same push twice.

The L12-09 fix turns the audit table into the **source of truth** for
claims:

1. `UNIQUE (user_id, rule, context_id)` on `public.notification_log`.
2. `public.fn_try_claim_notification(uuid, text, text) → boolean` —
   performs `INSERT ... ON CONFLICT DO NOTHING` and returns TRUE iff the
   caller inserted the row (i.e. owns the dispatch).
3. `public.fn_release_notification(uuid, text, text, integer)` — bounded
   rollback (≤ `p_max_age_seconds`, default 60 s) for callers whose
   dispatch failed after claiming. A row older than the bound is never
   deleted — this prevents a buggy caller from wiping a legitimate old
   notification.

Callers use the pattern:

```ts
const claimed = await tryClaimNotification(db, userId, rule, contextId);
if (!claimed) continue;            // someone else already dispatched
const ok = await dispatchPush(...);
if (!ok) await releaseNotificationClaim(db, userId, rule, contextId);
```

For rules with "once per day" semantics (`streak_at_risk`,
`inactivity_nudge`, `challenge_expiring`, `low_credits_alert`,
`onboarding_nudge`) the caller already encodes a UTC-date suffix into
`context_id`, so the UNIQUE constraint implements day-bucketed dedup
naturally.

---

## 2. Normal operation

### 2.1 What you see

| Metric | Source | Expected |
| --- | --- | --- |
| `notification_log` growth | `SELECT COUNT(*), MAX(sent_at) FROM public.notification_log;` | Monotonic, spiky around cron ticks. |
| `fn_try_claim_notification` returning FALSE | `notify-rules` logs | Only on legitimate dedup (retry after success). |
| Duplicate pushes in support inbox | ops triage | ~0; any report is a bug to investigate. |

### 2.2 Quick health query

```sql
-- Per-rule volume over the last 24 h.
SELECT rule, COUNT(*) AS dispatched
  FROM public.notification_log
 WHERE sent_at > now() - interval '24 hours'
 GROUP BY rule
 ORDER BY dispatched DESC;
```

```sql
-- Any pathological growth? (rows per rule, all time)
SELECT rule, COUNT(*) AS total, MIN(sent_at), MAX(sent_at)
  FROM public.notification_log
 GROUP BY rule
 ORDER BY total DESC
 LIMIT 20;
```

---

## 3. Operational scenarios

### 3.1 User reports receiving the same push twice

1. Pull the push history window:
   ```sql
   SELECT id, rule, context_id, sent_at
     FROM public.notification_log
    WHERE user_id = :user_id
      AND sent_at > now() - interval '24 hours'
    ORDER BY sent_at DESC;
   ```
2. If **two rows** for the same `(rule, context_id)` appear → the UNIQUE
   constraint was disabled or the migration hasn't landed. Verify:
   ```sql
   SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.notification_log'::regclass
      AND conname  = 'notification_log_dedup_unique';
   ```
   Expected: one row. If zero rows → rerun the L12-09 migration.
3. If **one row** but user saw two pushes → `send-push` (APNs/FCM) layer
   duplicated. Pull `send_push_audit` (L06-06) to confirm. Not an
   idempotency bug in the rules engine.

### 3.2 Expected push didn't arrive

1. Check whether a claim row exists:
   ```sql
   SELECT * FROM public.notification_log
    WHERE user_id = :user_id
      AND rule    = :rule
      AND context_id = :context_id;
   ```
2. If a row exists but no push → dispatch failed and `fn_release_notification`
   was not called (ex: Edge crashed mid-flight). Manually release:
   ```sql
   SELECT public.fn_release_notification(
     '00000000-0000-0000-0000-000000000000'::uuid,  -- user_id
     'streak_at_risk',                               -- rule
     '2026-04-21',                                   -- context_id
     60                                              -- max_age_seconds
   );
   ```
   The next cron tick will re-evaluate. **Caveat:** the 60 s bound means
   you can only release a claim within the first minute. Older claims are
   intentional. If you must re-notify the user, invoke `send-push`
   directly — do NOT bypass `notification_log`.
3. If no row exists → the rule evaluator excluded the user (check the
   rule's eligibility query). Not an idempotency issue.

### 3.3 Cleaning up historical duplicates

The migration runs a one-shot dedup (`ROW_NUMBER() OVER (PARTITION BY
user_id, rule, context_id ORDER BY sent_at, id) > 1` → delete) before
adding the constraint. If you need to re-run this manually (e.g. after a
partial rollback):

```sql
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id, rule, context_id
           ORDER BY sent_at ASC, id ASC
         ) AS rn
    FROM public.notification_log
)
DELETE FROM public.notification_log n
 USING ranked r
 WHERE n.id = r.id AND r.rn > 1;
```

---

## 4. Context-id conventions

| Rule | context_id format | Dedup granularity |
| --- | --- | --- |
| `challenge_received` | `{challenge_id}` | Once per invite ever. |
| `streak_at_risk` | `YYYY-MM-DD` | Once per user per UTC day. |
| `championship_starting` | `{championship_id}` | Once per championship ever. |
| `championship_invite_received` | `{championship_id}` | Once per invite ever. |
| `challenge_team_invite_received` | `{challenge_id}` | Once per invite ever. |
| `challenge_accepted` | `{challenge_id}:{joiner_user_id}` | Once per accept event. |
| `join_request_received` | `{group_id}:{athlete_name}` | Once per request. |
| `friend_request_received` | `{from_user_id}:{to_user_id}` | Once per invite pair. |
| `friend_request_accepted` | `{accepter_id}:{original_sender_id}` | Once per accept event. |
| `challenge_settled` | `{challenge_id}` | Once per settlement. |
| `challenge_expiring` | `{challenge_id}:YYYY-MM-DD` | Once per user per day (re-fires if challenge extended). |
| `inactivity_nudge` | `YYYY-MM-DD` | Once per user per UTC day. |
| `badge_earned` | `{user_id}:{badge_id}` | Once per badge award. |
| `league_rank_change` | `{group_id}:{new_rank}` | Once per user per rank transition. |
| `join_request_approved` | `{group_id}:{user_id}` | Once per approval. |
| `low_credits_alert` | `low_credits:{group_id}:YYYY-MM-DD` | Once per group per UTC day. |
| `onboarding_nudge` | `d{daysSinceRegistration}` (0..7) | Once per day-slot. |

**Adding a new rule:** decide whether it's event-driven (immutable id) or
recurring (include a time bucket). A recurring rule WITHOUT a time
bucket in `context_id` will dedup **forever** after the first dispatch —
this is almost always wrong. The legacy 12-hour window from
`wasRecentlyNotified` no longer exists.

---

## 5. Rollback

Rolling back the UNIQUE constraint re-introduces the race. If you must:

```sql
ALTER TABLE public.notification_log
  DROP CONSTRAINT IF EXISTS notification_log_dedup_unique;

-- Optional: drop the helper RPCs.
DROP FUNCTION IF EXISTS public.fn_try_claim_notification(uuid, text, text);
DROP FUNCTION IF EXISTS public.fn_release_notification(uuid, text, text, integer);
```

The Edge Functions fall back to the legacy `wasRecentlyNotified` +
`INSERT` path when the RPC is missing, so a partial rollback is safe
(behaviour regresses to pre-L12-09 but nothing breaks).

---

## 6. Observability signals

* **Claim-loss rate** — query
  `SELECT COUNT(*) FROM public.notification_log WHERE sent_at > now() - interval '1 hour'`
  vs the count of "would have dispatched" from `notify-rules` logs.
  Healthy ratio: ~1:1. A large gap indicates either high dispatch
  failure (investigate `send-push`) or heavy duplicate traffic (normal
  during a cron/operator collision).
* **Expected push missing** — `portal_audit_log` and user support
  tickets. Cross-reference with `notification_log` rows for the user.
* **Growing duplicates** — `SELECT user_id, rule, context_id, COUNT(*)
  FROM public.notification_log GROUP BY 1,2,3 HAVING COUNT(*) > 1` must
  return zero rows. Any row = constraint violated or dropped.

---

## 7. Related

* L06-04 — cron health alerts
* L06-05 — Edge Function retry wrapper
* L12-03 — cron overlap protection
* L15-04 — transactional email platform (complementary dedup)
