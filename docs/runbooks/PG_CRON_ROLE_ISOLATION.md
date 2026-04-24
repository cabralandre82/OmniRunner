# pg_cron Role Isolation Runbook (L12-10)

## Why this runbook exists

`pg_cron` jobs in Supabase run as the **role that owns the function the
schedule invokes**. The default Supabase project provisions all
migrations as `postgres` (a superuser), so by default every cron job
inherits superuser privileges. A bug in a scheduled function
(e.g. SQL injection inside a notification template) would therefore
have superuser blast-radius.

We ship our scheduled work under the `cron_worker` role, which has
exactly the privileges each job needs and nothing else. This runbook
documents:

1. The threat model that drives the role split.
2. The role definition (DDL + grants) we apply at provision time.
3. How to add a new scheduled function under this role.
4. How to audit drift (`SELECT … FROM cron.job` joined with
   `pg_proc`).

> See also: `docs/runbooks/CRON_HEALTH_RUNBOOK.md` for the
> observability layer (alerts when a scheduled job fails or breaches
> SLA), and `docs/runbooks/CRON_SLA_RUNBOOK.md` for the SLA
> definitions.

---

## 1. Threat model

| Threat                                              | Mitigation                                          |
|-----------------------------------------------------|-----------------------------------------------------|
| SQL injection inside a scheduled `INSERT/UPDATE`    | `cron_worker` cannot drop tables or alter roles.    |
| Compromised webhook secret used in a cron-invoked Edge Function | `cron_worker` cannot read `vault.decrypted_secrets`.|
| Bug in a `SECURITY DEFINER` helper that escalates to superuser | `cron_worker` is the *invoker* — `SECURITY DEFINER` must be granted explicitly per function. |
| Operator forgetting to `REVOKE` after a one-shot job | `cron_worker` privileges are reviewed every release via the constraint guard described in §4. |

---

## 2. Role definition

```sql
-- Provisioned by ops. Idempotent — safe to re-run.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'cron_worker') then
    create role cron_worker noinherit nologin;
  end if;
end
$$;

-- Functional grants — minimal set required by today's scheduled jobs.
grant usage on schema public to cron_worker;
grant select, insert, update on
  public.coin_ledger,
  public.notification_log,
  public.cron_run_state,
  public.cron_health_alerts,
  public.cron_edge_retry_attempts,
  public.audit_logs
  to cron_worker;

-- Edge invocation helpers (L06-05). Read-only on secrets.
grant execute on function
  public.fn_invoke_edge_with_retry(text, jsonb, integer),
  public.fn_invoke_clearing_cron_safe(),
  public.fn_invoke_archive_sessions_safe()
  to cron_worker;

-- Custody / clearing / wallet-credit functions stay locked to
-- service_role: cron_worker MUST go through the Edge Function
-- (which carries its own auth) for those mutations.
revoke execute on function
  public.execute_burn_atomic(uuid, uuid, numeric),
  public.execute_withdrawal(uuid, uuid, numeric, text)
  from cron_worker;
```

The `noinherit` flag means a future `GRANT cron_worker TO …` on a
human role does NOT silently grant the worker's privileges to the
person — they must `SET ROLE cron_worker` explicitly to perform a job
manually.

---

## 3. Scheduling a job under `cron_worker`

Use `cron.schedule_in_database` with explicit `database_name`, then
`UPDATE cron.job SET username = 'cron_worker'` because the SDK does
not yet expose the `username` argument.

```sql
-- 1. Schedule (runs as creator role by default)
select cron.schedule(
  'reconcile-wallets-daily',
  '15 4 * * *',
  $$select public.fn_invoke_edge_with_retry(
    'reconcile-wallets',
    jsonb_build_object(),
    3
  )$$
);

-- 2. Re-attach to cron_worker
update cron.job
  set username = 'cron_worker'
  where jobname = 'reconcile-wallets-daily';
```

Add a `do $$ … $$` self-test in the same migration that asserts the
role re-attachment landed:

```sql
do $$
declare
  v_role text;
begin
  select username into v_role from cron.job
    where jobname = 'reconcile-wallets-daily';
  if v_role is distinct from 'cron_worker' then
    raise exception 'L12-10: cron job % runs as % (expected cron_worker)',
      'reconcile-wallets-daily', v_role
      using errcode = 'P0010';
  end if;
end
$$;
```

---

## 4. Drift audit query

Run weekly (or wire into `cron-health-monitor`):

```sql
select
  jobname,
  username,
  active,
  schedule
from cron.job
where username not in ('cron_worker', 'service_role')
order by jobname;
```

Any row that comes back is a job still running under a privileged
role. Investigate the migration that created it; either:

* re-attach to `cron_worker` (preferred) and grant the missing
  privilege explicitly, or
* document the exception inline next to `cron.schedule(...)` with a
  `-- L12-10-OK: <reason>` comment so the lockstep linter
  (planned in L12-13) doesn't fail.

---

## 5. Operational hooks

* **Alerting** — `cron-health-monitor` reads `cron_health_alerts`;
  any `cron.job` row whose `username` flips back to `postgres`
  outside a maintenance window writes a `severity=high` alert
  there.
* **Recovery** — to manually rerun a job under `cron_worker` from
  psql: `set role cron_worker; select fn_invoke_edge_with_retry(...);`.
* **Rollback** — emergency only: `update cron.job set username =
  'postgres' where jobname = '...'; select cron.alter_job(...);`.
  Document in the incident postmortem and revert before the next
  release.

---

## 6. References

* [pg_cron README — roles & permissions](https://github.com/citusdata/pg_cron#installing)
* `docs/runbooks/CRON_HEALTH_RUNBOOK.md`
* `docs/runbooks/CRON_SLA_RUNBOOK.md`
* `docs/audit/findings/L12-10-jobs-pg-cron-executam-como-superuser-padrao.md`
