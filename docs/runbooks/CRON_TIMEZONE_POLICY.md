# Cron Timezone Policy (L12-12)

## TL;DR

* **All `pg_cron` schedules are expressed in UTC.** No exceptions.
* **Calendar-aware cutoffs** (e.g. "settle today's clearing")
  resolve `now()` against `America/Sao_Paulo` inside the
  *function the cron invokes*, never inside the schedule string.
* **DST is irrelevant for Brazil** (abolished in 2019, see
  Decreto 9.772/2019). A future US/EU expansion adds a per-tenant
  `business_timezone` column to the relevant entity table; the cron
  schedule stays UTC and the helper function does the conversion.

This document codifies the decision so future contributors do not
re-litigate "should we just run it at 03:00 BRT instead of 06:00
UTC?" every six months.

---

## 1. Context

`pg_cron` schedule strings are `cron`-syntax with the database server
timezone hard-coded by the Supabase platform to `UTC`. There is no
per-job timezone field. Two approaches were considered:

### Option A — Express schedules in UTC (chosen)

Pros:
* Single source of truth for "when does it run" — readable from
  `cron.job.schedule` without joining anything.
* Immune to DST transitions: a 03:00 UTC job runs at the same wall
  clock instant year-round.
* CI-friendly: lint can compare `cron.job.schedule` strings to
  documented expectations.

Cons:
* Operators have to mentally convert UTC → local when reading
  `cron.job` rows.
* "Run at 03:00 BRT" requires `15 6 * * *` (BRT offset is UTC-3).

Mitigation for the readability con: every cron entry MUST include a
trailing comment with the local intent, e.g.:

```sql
select cron.schedule(
  'clearing-cron',
  '15 3 * * *',  -- 00:15 BRT (UTC-3) — after midnight, before market open
  $$ ... $$
);
```

### Option B — Express schedules in local time, convert at runtime

Rejected because:
* DST transitions cause double-fires and skipped fires (24-hour
  window where the same wall-clock time happens twice or never).
  Brazil is safe today, but the codebase is meant to be re-deployable
  in any region.
* No first-class support in `pg_cron` — would require a wrapper that
  re-schedules itself at DST boundaries, which is its own DoS source.

---

## 2. Calendar-aware cutoffs

When a job needs to settle "today's data", the schedule alone cannot
express that. We use a SECURITY DEFINER helper that converts `now()`
to the business timezone, truncates to day, then converts back to UTC.

Canonical example — `fn_clearing_cutoff_utc` (L12-08):

```sql
create or replace function public.fn_clearing_cutoff_utc(
  p_timezone text default 'America/Sao_Paulo',
  p_as_of    timestamptz default null
) returns timestamptz
language sql
stable
as $$
  select (date_trunc('day', coalesce(p_as_of, now()) at time zone p_timezone))
    at time zone p_timezone;
$$;
```

The cron schedule then uses the helper:

```sql
select cron.schedule(
  'clearing-cron',
  '15 3 * * *',  -- 00:15 BRT (UTC-3)
  $$
  select public.fn_invoke_clearing_cron_safe(
    p_cutoff_utc => public.fn_clearing_cutoff_utc(),
    p_run_kind   => 'scheduled'
  );
  $$
);
```

The helper is also exposed for replay via `p_as_of` — operators can
re-run a specific day from psql without changing the cron string.

---

## 3. Future US / EU expansion checklist

When (not if) we add a tenant outside America/Sao_Paulo:

1. Add `business_timezone text not null` to the relevant entity table
   (`coaching_groups`, `custody_accounts`, etc.). Default to
   `'America/Sao_Paulo'` for backfill.
2. Add a `CHECK fn_is_valid_timezone(business_timezone)` constraint
   (helper from L12-07).
3. Pass the per-tenant timezone into the cutoff helper via
   `fn_clearing_cutoff_utc(p_timezone => x.business_timezone)`.
4. **DO NOT** change the cron schedule string. The job still fires at
   the same UTC instant; the helper now produces a different cutoff
   per tenant.
5. Add a per-tenant rollup of "what UTC instant is your local 03:00"
   to the admin dashboard so operators see when the job will run for
   each tenant.

---

## 4. Operational guidance

* **Listing schedules** — `select jobname, schedule, command from
  cron.job order by jobname;` always shows UTC. Pair with the
  trailing `-- HH:MM BRT` comment in the migration source for
  readability.
* **Testing locally** — Postgres `set timezone = 'UTC'; select
  fn_clearing_cutoff_utc();` to reproduce production behaviour.
* **Replay** — `select fn_invoke_clearing_cron_safe(
  p_cutoff_utc => fn_clearing_cutoff_utc(p_as_of => '2026-04-21 17:00 UTC'),
  p_run_kind   => 'manual_replay'
  );`.
* **Drift audit** — every cron schedule should have a trailing comment
  in its migration source; CI guard `audit:cron-idempotency`
  (L12-11) covers idempotency, the `audit:cron-tz` follow-up
  (planned) will cover the comment.

---

## 5. References

* [PostgreSQL docs — timezone conversions](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-TIMEZONECASTS)
* `docs/runbooks/CLEARING_CRON_CUTOFF_RUNBOOK.md` (L12-08)
* `docs/runbooks/ONBOARDING_NUDGE_TIMEZONE_RUNBOOK.md` (L12-07)
* `docs/audit/findings/L12-12-timezone-do-cron-utc-ok-mas-horario-dst.md`
