# Backup / restore runbook — L04-08

> Operational playbook for executing the policies declared in
> [`docs/compliance/BACKUP_POLICY.md`](../compliance/BACKUP_POLICY.md).
>
> **Finding:** [`L04-08`](../audit/findings/L04-08-backups-supabase-sem-politica-de-retencao-documentada.md)
> **Guard CI:** `npm run audit:backup-policy`

---

## 1. On-call roles

- **Incident commander** — owns the decision to restore and
  communicates with stakeholders.
- **Restore operator** — executes the restore commands and the
  post-restore scrubbing.
- **DPO delegate** — present whenever the restore is triggered by
  or during an open LGPD erasure request. Approves §5 scrubbing.

## 2. When to restore

| Trigger                                        | Path        |
|------------------------------------------------|-------------|
| Accidental row loss, last < 7 days             | PITR        |
| Accidental schema change, last < 7 days        | PITR        |
| Cluster unavailable / corruption               | Daily snap  |
| Cross-region outage                            | Weekly snap |
| Fiscal / regulatory replay (> 14 days ago)     | Monthly snap |
| Post-mortem forensics                          | Cold copy   |

If in doubt, prefer **PITR** for rows and **daily snapshot** for
schema — they are the freshest.

## 3. PITR restore (< 7 days)

> **Destination:** by default, a **new** Supabase project. Never
> restore over production unless the incident commander approves.

1. Capture the target wall-clock: `TARGET=<ISO-8601 UTC>`.
2. Open a ticket in the SRE log with the `TARGET`, reason, and
   whether an open erasure request is in flight.
3. In Supabase dashboard → Database → Backups → PITR:
   open the restore wizard, pick `TARGET`, destination = new project.
4. Wait for restore (~15-60 min).
5. Run `SELECT now(), max(created_at) FROM public.sessions;`
   on the restored project — compare with `TARGET`.
6. If an erasure request was confirmed **after** `TARGET`, go to §5
   **before** routing any traffic.
7. Smoke tests: `npm run audit:verify` against the restored project.

## 4. Snapshot restore (daily / weekly / monthly)

1. Capture snapshot ID: `SNAP=<supabase-snapshot-id>`.
2. Same ticket-opening procedure as §3.
3. In Supabase dashboard → Database → Backups → Snapshots:
   restore `SNAP` into a new project.
4. If the snapshot is > 7 days old (weekly) or > 30 days (monthly),
   the schema may be behind the current `master`. Apply the
   catch-up migrations from the repo in timestamp order until
   `SELECT count(*) FROM supabase_migrations.schema_migrations;`
   matches the repo expectation.
5. Same scrubbing gate as §5.
6. Same smoke tests as §3.

## 5. Post-restore PII scrubbing (erasure request in flight)

This step is **mandatory** if any of the following is true:

- An LGPD erasure request was confirmed **after** the backup's
  `TARGET` or `SNAP` timestamp.
- The incident commander flagged the ticket as "contains
  previously-erased users".

Procedure:

```sql
-- DPO delegate approves the list of user_ids first.
-- Replace $ERASED_IDS with the JSON array from the erasure log.

BEGIN;

-- 1. auth.users — cascades to dependent tables via FK ON DELETE CASCADE.
DELETE FROM auth.users
 WHERE id = ANY ($ERASED_IDS::uuid[]);

-- 2. Tables without FK cascade (check before each restore — the set
--    grows over time). Today: strava_tokens, portal_audit_log,
--    coin_ledger_pii_redactions, and any table the DPO delegate lists.
DELETE FROM public.strava_tokens     WHERE user_id = ANY ($ERASED_IDS::uuid[]);
DELETE FROM public.portal_audit_log  WHERE actor_id = ANY ($ERASED_IDS::uuid[]);

-- Immutable append-only tables (L10-08) cannot be deleted from
-- without the retention bypass (L08-08). This is deliberate —
-- the audit trail itself is legally required to outlive erasure
-- (LGPD Art. 18 §4 c/c Art. 7 VI "accountability").
-- Reference the DPO decision + ticket ID in the scrubbing log
-- explaining why the row remains.

COMMIT;
```

Record the scrubbed user_ids in
`docs/compliance/restore-drills/<YYYY-MM-DD>-<ticket>.md` together
with the DPO delegate's sign-off.

## 6. Staging obfuscation

Whenever we refresh staging from production, run the obfuscation
script **immediately** after restore, before granting access to
engineers:

```sql
BEGIN;

UPDATE auth.users
   SET email = 'user_' || id::text || '@stg.omnirunner.dev',
       raw_user_meta_data = '{}'::jsonb,
       raw_app_meta_data  = '{"env":"staging"}'::jsonb;

UPDATE public.profiles
   SET full_name         = 'User ' || substr(id::text, 1, 8),
       phone             = '+55 11 9xxxx-xxxx',
       instagram_handle  = NULL,
       tiktok_handle     = NULL;

UPDATE public.strava_tokens
   SET access_token  = 'STG-INVALID-' || id::text,
       refresh_token = 'STG-INVALID-' || id::text,
       expires_at    = now() - interval '1 day';

COMMIT;
```

## 7. Restore drills (quarterly)

1. Pick a weekday afternoon, low-risk window.
2. Execute §4 against the most recent daily snapshot into a
   one-off project named `restore-drill-<YYYY-Qx>`.
3. Record:
   - decision time,
   - restore complete time (wall clock),
   - schema catch-up time,
   - smoke-test pass/fail.
4. Tear down the project within 7 days of the drill. Keep the
   markdown record in `docs/compliance/restore-drills/`.

Missing a quarterly drill is a reportable event — the SRE lead
files a self-finding `L04-08-drill-missed-YYYY-Qx` in the audit
registry and the backlog bumps the drill to the next sprint.

## 8. Cross-links

- [`BACKUP_POLICY.md`](../compliance/BACKUP_POLICY.md)
- [`L04-08 finding`](../audit/findings/L04-08-backups-supabase-sem-politica-de-retencao-documentada.md)
- [`L04-09 finding`](../audit/findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md)
- [`L08-08 runbook`](./AUDIT_LOGS_RETENTION_RUNBOOK.md)
- [`L10-08 migration`](../../supabase/migrations/20260421350000_l10_08_audit_logs_append_only.sql)
  — append-only tables cannot be deleted from, even during
  post-restore scrubbing.
