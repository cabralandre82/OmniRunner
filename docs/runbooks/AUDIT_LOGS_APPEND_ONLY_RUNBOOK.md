# Audit logs append-only runbook (L10-08)

> **Linked finding:** [`L10-08`](../audit/findings/L10-08-logs-de-acesso-sensiveis-sem-imutabilidade.md)
> **Owner:** Platform / Security
> **CI check:** `npm run audit:audit-logs-append-only`
> **Test suite:** `npx tsx tools/test_l10_08_audit_logs_append_only.ts`

## 1. Why this exists

Before L10-08, every audit-style table (`portal_audit_log`,
`coin_ledger_pii_redactions`, `cron_edge_retry_attempts`, `consent_events`,
…) was a regular table. Any caller holding the `service_role` key — an
edge function, a migration, a DBA's psql session — could run `DELETE`
or `UPDATE` and silently rewrite history. That collapsed the core
invariant the CSO lens flagged: an incident investigator who queries
the trail 90 days later would not be able to distinguish *"event never
happened"* from *"event happened and was scrubbed."*

The fix moves the invariant into the database itself: every protected
table gets a `BEFORE UPDATE OR DELETE` (row) and `BEFORE TRUNCATE`
(statement) trigger that raises `P0010` with a machine-readable
reason. The only way to mutate a row is to ship a reviewed migration
that temporarily drops the trigger — which is visible in `git log` and
goes through CI/code-review, the exact audit trail we need.

## 2. What we shipped

### 2.1 Registry + installer

`public.audit_append_only_config(schema_name, table_name, mode, applied_at, note)`
lists every protected table. `mode` is one of:

- `strict` — no UPDATE, no DELETE, no TRUNCATE. Ever.
- `append_with_outcome` — the table has its own per-column
  immutability trigger (e.g. `account_deletion_log` from L04-02) that
  permits a single terminal write. The generic guard is **not**
  installed here; the registry entry is purely informational.

Bindings are installed via:

```sql
SELECT public.fn_audit_install_append_only_guard('public', 'portal_audit_log');
```

The installer is idempotent and a no-op when the target table does not
exist in this environment (useful for sandboxes / partial schemas).

### 2.2 Trigger

The BEFORE trigger emits `RAISE WARNING 'L10-08: attempt to <OP> append-only audit table <schema>.<table> by session_user=<s> current_user=<c>'` and
then `RAISE EXCEPTION` with `ERRCODE='P0010'` and `DETAIL` of
`append_only_delete_blocked` / `append_only_update_blocked` /
`append_only_truncate_blocked`.

Because the transaction rolls back, nothing gets persisted in a DB
table — by design. Postgres log capture (Logflare, Grafana, Datadog)
scrapes the WARNING line and any attempt shows up in the observability
plane with full context (session_user + current_user identify the
caller even when the raise happens under service_role).

### 2.3 Detection

- `public.fn_audit_has_append_only_guard(schema, table)` — boolean
  helper.
- `public.fn_audit_assert_append_only_shape()` — raises `P0010` if:
  - any row in `audit_append_only_config` with `mode='strict'` has
    lost its trigger, OR
  - any table from the canonical known-audit list (`portal_audit_log`,
    `coin_ledger_pii_redactions`, `cron_edge_retry_attempts`,
    `wallet_drift_events`, `custody_daily_cap_changes`,
    `consent_events`, `audit_logs`) exists in the DB without a
    registry entry.

The canonical list is hardcoded in `fn_audit_assert_append_only_shape`
so an engineer who adds a new audit-style table **must** either
register it or extend both the helper and the migration explicitly —
the CI check refuses to let it pass silently.

## 3. Operational playbooks

### 3.1 "I need to mutate a row — what do I do?"

1. Decide whether the mutation is really justified. If the answer is
   "we saved PII by mistake" → prefer adding a redaction helper (see
   L04-07 pattern) that replaces the PII *in the same row* without
   deleting the event. If the answer is "this event was logged twice
   due to a cron race" → add a dedup key (see L12-09 pattern) rather
   than deleting.
2. If you still need a raw mutation, ship a new migration
   (`<ts>_mutate_<table>_<ticket>.sql`) that:

   ```sql
   BEGIN;

   DROP TRIGGER IF EXISTS trg_portal_audit_log_append_only_row
     ON public.portal_audit_log;

   -- your UPDATE / DELETE here, tightly scoped.

   SELECT public.fn_audit_install_append_only_guard('public', 'portal_audit_log');

   COMMIT;
   ```

3. The migration goes through code review (two eyes, the CSO lens).
   The `git log` of the migration is the audit trail of who approved
   the mutation and why.

### 3.2 Adding a new audit-style table

1. Create the table + RLS + indexes as usual.
2. At the end of the same migration, call:

   ```sql
   SELECT public.fn_audit_install_append_only_guard('public', '<new_table>', 'L<NN>-XX: purpose');
   ```

3. If the table is part of the "canonical" set covered by
   `fn_audit_assert_append_only_shape`, extend the helper's `v_known`
   array in a follow-up migration (deliberately a two-step so the CI
   guard stays minimal by default).

### 3.3 Investigating a trigger fire in production

1. Filter Logflare for `L10-08: attempt to`. Every blocked mutation
   emits exactly one WARNING line.
2. Extract `session_user` and `current_user`. In Supabase, the expected
   pairing is `session_user=authenticator` + `current_user=service_role`
   when an edge function hits the DB, or `postgres` for both when a
   DBA uses psql.
3. If neither matches, raise an incident — someone minted a rogue
   connection string.

### 3.4 Sandbox / fresh install

Environments where one of the canonical tables never existed (e.g. a
fresh Supabase project that hasn't run the older migrations) see
`RAISE NOTICE '[L10-08] <table> not present — skipping guard install'`
and move on. The CI check (`fn_audit_assert_append_only_shape`)
flags only tables that **do** exist without a binding — it never
fails because of a sandbox lacking optional extensions.

## 4. Rollback

Full rollback (not recommended — returns to the pre-L10-08 invariant):

```sql
BEGIN;

DROP TRIGGER IF EXISTS trg_portal_audit_log_append_only_row
  ON public.portal_audit_log;
-- … one per registered table …
DROP FUNCTION public.fn_audit_reject_mutation();
DROP FUNCTION public.fn_audit_install_append_only_guard(text, text, text);
DROP FUNCTION public.fn_audit_has_append_only_guard(text, text);
DROP FUNCTION public.fn_audit_assert_append_only_shape();
DROP TABLE public.audit_append_only_config;

COMMIT;
```

Per-table rollback (for a targeted incident): drop only the two
triggers on that one table, leave the registry / helpers / other
bindings intact.

## 5. Related findings

- L04-02 / L06-08 — `account_deletion_log` has its own column-level
  immutability trigger; L10-08 registers it as `append_with_outcome`.
- L04-07 — `coin_ledger_pii_redactions` is an audit table; L10-08
  installs the strict guard on it.
- L06-04 — `cron_health_alerts` has UPDATE semantics for `acknowledged_at`
  and is deliberately **not** enrolled in L10-08.
- L10-07 — zero-trust JWT validation. Pairs with L10-08: once the
  token is verified, every write to the trail is cryptographically
  attributable to the correct actor and can never be rewritten.
- L10-09 — anti credential stuffing. Login attempts are in
  `auth_login_attempts` which is deliberately mutable (counter
  semantics) and therefore not enrolled here.
