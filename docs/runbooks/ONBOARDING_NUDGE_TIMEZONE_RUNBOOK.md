# Onboarding-Nudge Timezone Runbook

> **Audit refs:** L12-07 · L07-06 · **Owner:** coo/cxo · **Severity:** 🟠 High
> **Migration:** `supabase/migrations/20260421260000_l12_07_onboarding_nudge_user_timezone.sql`
> **Edge Function:** `supabase/functions/onboarding-nudge/index.ts`
> **Integration tests:** `tools/test_l12_07_onboarding_nudge_timezone.ts`
> **Related:** NOTIFICATION_IDEMPOTENCY_RUNBOOK.md · EDGE_RETRY_WRAPPER_RUNBOOK.md

---

## 1. Summary

Onboarding nudges (D0-D7 pushes) used to fire once a day at 10:00 UTC
(= 07:00 BRT), which the audit flagged as too early for the BR-first
user base and blind to users in other timezones. L12-07 moves the
schedule to hourly and lets each user's own timezone +
`notification_hour_local` decide whether this particular hour is the
one that should send the push.

L12-09 dedup (`UNIQUE (user_id, rule, context_id)` with `context_id =
"d${daysSinceRegistration}"`) still guarantees at most one push per
user per day — the hourly loop just filters down to the right hour
per user.

Schema additions to `public.profiles`:

| Column | Type | Default | Purpose |
| --- | --- | --- | --- |
| `timezone` | `text NOT NULL` | `'America/Sao_Paulo'` | IANA zone used by all user-local schedulers |
| `notification_hour_local` | `smallint NOT NULL` | `9` | Hour-of-day (0..23) at which daily pushes may fire |

Helpers:

| Function | Purpose |
| --- | --- |
| `fn_is_valid_timezone(text) → boolean` | CHECK constraint for the `timezone` column; also callable from TS |
| `fn_user_local_hour(uuid) → smallint` | Current hour in user's TZ (0..23), with safe fallback |
| `fn_should_send_nudge_now(uuid, preferred?)` | `TRUE` iff `fn_user_local_hour` matches the user's preferred hour |

Cron: renamed from `onboarding-nudge-daily` to
`onboarding-nudge-hourly`; schedule is now `0 * * * *` and it still
invokes `public.fn_invoke_onboarding_nudge_safe()` which benefits
from L06-05 retry + L12-03 overlap protection.

---

## 2. Normal operation

### 2.1 Dashboard checks

```sql
-- Cron lifecycle for the hourly nudge job.
SELECT name, last_status, last_started_at, last_finished_at, last_meta
  FROM public.cron_run_state
 WHERE name = 'onboarding-nudge-hourly';

-- How many hourly invocations in the last 24h actually dispatched?
SELECT date_trunc('hour', started_at) AS bucket,
       count(*)                        AS attempts,
       count(*) FILTER (WHERE http_status BETWEEN 200 AND 299) AS ok
  FROM public.cron_edge_retry_attempts
 WHERE job_name = 'onboarding-nudge-hourly'
   AND started_at > now() - interval '24 hours'
 GROUP BY 1 ORDER BY 1 DESC;

-- Timezone distribution across the user base.
SELECT timezone, count(*) AS n
  FROM public.profiles
 GROUP BY 1 ORDER BY n DESC
 LIMIT 20;

-- Histogram of preferred notification hours.
SELECT notification_hour_local, count(*) AS n
  FROM public.profiles
 GROUP BY 1 ORDER BY 1;
```

### 2.2 Healthy shape

* `cron_run_state.last_status = 'ok'` on most of the 24 hourly ticks.
  It is perfectly normal for 23 of 24 responses to report
  `evaluated: 0` — only the hour that matches the user cohort's
  preferred hour dispatches pushes.
* Response body `skipped_off_hour >> evaluated` is expected: every
  registered-in-last-7-days profile that isn't at its preferred hour
  right now is skipped.
* Retry audit shows the vast majority as `http_status=200` on first
  attempt.

---

## 3. Operational scenarios

### 3.1 "I never received an onboarding nudge"

1. Confirm the user is in the D0-D7 window:
   ```sql
   SELECT id, created_at, now() - created_at AS age,
          timezone, notification_hour_local
     FROM public.profiles
    WHERE id = '<user_uuid>';
   ```
   If `age > 7 days`, the user is out of the onboarding window and the
   cron will not attempt them anymore.
2. Confirm their preferred hour exists and matches their expectation
   (default = 9 → 09:00 in their local time).
3. Confirm a dispatch attempt was made (L12-09 log):
   ```sql
   SELECT sent_at, context_id
     FROM public.notification_log
    WHERE user_id = '<user_uuid>'
      AND rule = 'onboarding_nudge'
    ORDER BY sent_at DESC LIMIT 10;
   ```
   Each `context_id = 'd<N>'` row means a claim was made for that day.
   Missing row → the nudge was never attempted. Row present but no
   push on device → `send-push` problem (see `EDGE_RETRY_WRAPPER_RUNBOOK`
   cross-ref + provider dashboards).
4. Check the user's preferred hour against current local hour:
   ```sql
   SELECT public.fn_user_local_hour('<user_uuid>') AS now_local_hour,
          notification_hour_local                   AS preferred,
          public.fn_should_send_nudge_now('<user_uuid>') AS would_fire_now
     FROM public.profiles
    WHERE id = '<user_uuid>';
   ```

### 3.2 User asks for a different nudge hour

1. Guide the user (or operator on their behalf) to update
   `notification_hour_local`:
   ```sql
   UPDATE public.profiles
      SET notification_hour_local = 20   -- 8pm local
    WHERE id = '<user_uuid>';
   ```
   The CHECK enforces `0..23`. No reschedule needed — the hourly cron
   picks up the new value on the next tick.
2. Timezone override follows the same pattern:
   ```sql
   UPDATE public.profiles
      SET timezone = 'America/Recife'
    WHERE id = '<user_uuid>';
   ```
   Invalid IANA zones (including `'America/Sao Paulo'` with a space)
   are rejected by `profiles_timezone_valid` CHECK.
3. First login on the mobile app / portal SHOULD detect the browser
   TZ and pin it via a PATCH to `/api/profile`. If a user swaps
   timezones (travel, relocation), they can edit it themselves from
   settings.

### 3.3 The hourly invocation storm is loud

If you watch `cron_run_state` and notice 24 invocations per day, that
is **expected** — the cron fires every hour. Noise reduction options:

* **Hourly schedule with per-user hour filter (current default)** —
  23/24 invocations are near-no-ops that just SELECT the last-7-days
  cohort and skip every row. The SELECT is served by the existing
  index on `profiles(created_at)`.
* If the near-no-ops are still too noisy, change the cron schedule to
  run only during "any user's preferred hour" window. E.g., if the
  config distribution is clustered 07:00-20:00, restrict to
  `'0 7-20 * * *'` — reduces ticks to ~14/day.
* Extreme option: sharded schedules per TZ bucket. Not recommended
  until we have >50 distinct TZs in production.

### 3.4 Historical user has `timezone = NULL`

This cannot happen post-migration (the column is `NOT NULL DEFAULT
'America/Sao_Paulo'`). If you see NULL somewhere, the Edge Function
still defaults to Sao_Paulo/9 — but investigate: the NOT NULL is a
hard invariant.

---

## 4. Interactions with other features

### 4.1 `notify-rules` (16 notification rules)

`notify-rules` currently runs every 5 minutes and is event-driven
(streak threshold, challenge expiring, etc.) — not tied to a wall
clock. L12-07 does NOT change its schedule. If a future rule needs
"once per day in user local morning" semantics, call
`fn_should_send_nudge_now(user_id)` or inline the Intl-based hour
check already used by `onboarding-nudge/index.ts`.

### 4.2 `clearing-cron` (L12-08, pending)

L12-08 tracks the same TZ concern for the clearing cron. When that
fix lands, it will probably use `fn_user_local_hour` / a group-level
timezone column via `custody_accounts.daily_limit_timezone` (already
available from L05-09).

### 4.3 `sessions.start_time_ms` display (L07-06 scope)

`profiles.timezone` is now available to the portal / mobile app for
formatting session timestamps server-side. Consumer work is tracked
separately (not in this migration).

---

## 5. Tunables

| Parameter | Default | Notes |
| --- | --- | --- |
| cron schedule | `0 * * * *` | Hourly tick; each invocation is near-no-op except during matching user hour |
| default timezone | `America/Sao_Paulo` | BR-first product decision |
| default preferred hour | `9` | "After morning commute, before standup" |
| D0-D7 window | 7 days | Matches `NUDGE_MESSAGES` table in the Edge Function |
| Edge retry `max_attempts` | 3 | L06-05 retry wrapper |
| Edge retry `backoff_base` | 10 s | L06-05 retry wrapper |

---

## 6. Rollback

If something goes wrong with the hourly schedule, rollback to the old
daily 10:00 UTC cadence via:

```sql
SELECT cron.unschedule('onboarding-nudge-hourly');
SELECT cron.schedule(
  'onboarding-nudge-daily',
  '0 10 * * *',
  $cron$ SELECT public.fn_invoke_onboarding_nudge_safe(); $cron$
);
```

The per-user filter in `onboarding-nudge/index.ts` will still apply —
but because the cron only fires once a day at 10:00 UTC (= 07:00 BRT,
the very hour we are trying to avoid), most users will be SKIPPED and
nobody will get a nudge. Prefer reverting the Edge Function hunk
(remove the `localHour !== userPrefHour` guard) together with the
schedule reversion if you truly need the old behaviour back.

`profiles.timezone` and `profiles.notification_hour_local` are safe
to leave installed regardless — they are additive and consumed by
other features (admin reporting, session timestamps).

---

## 7. Observability signals

* **Spike in `skipped_off_hour` with `evaluated = 0` for >6 hours** —
  all users have skewed hour preferences, OR server clock drifted, OR
  timezone data corrupt. Run a sample `fn_user_local_hour` + compare
  with an external NTP source.
* **`cron_run_state.last_status = 'failed'` on more than 2 ticks
  in 24h** — Edge Function flaking. See EDGE_RETRY_WRAPPER_RUNBOOK.
* **`profiles` rows with `timezone = 'UTC'` growing** — probably an
  app bug pinning the wrong default on iOS/Android; open an issue to
  align mobile detection logic with
  `Intl.DateTimeFormat().resolvedOptions().timeZone`.

---

## 8. Related

* L07-06 — `profiles.timezone` column (closed alongside L12-07)
* L12-07 — this runbook
* L12-08 — clearing-cron timezone (pending)
* L12-09 — notification_log idempotency
* L06-05 — Edge Function retry wrapper
* L12-03 — cron overlap protection (cron_run_state)
