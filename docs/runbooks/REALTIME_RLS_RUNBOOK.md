# Realtime RLS Runbook (L02-08)

Operational guide for the **`supabase_realtime` publication safety guard**
that prevents accidental cross-tenant CDC leaks. Covers the diagnostic
helpers and the DDL event trigger introduced by
`supabase/migrations/20260419160000_l02_realtime_rls_guard.sql`.

> Audience: any engineer adding a table to Supabase Realtime, or
> debugging an unexpected `REALTIME_RLS_VIOLATION` error during a
> migration. Read time ~ 4 min.

## Architecture — 30-second recap

```
   ┌─────────────┐    1. Authenticated client opens WS to
   │  Browser /  │       /realtime/v1/websocket
   │  Flutter    │       and subscribes with channel filters
   └──────┬──────┘
          │
          ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ Supabase Realtime broker                                     │
   │  ─ replays logical CDC stream from supabase_realtime publn   │
   │  ─ for each row event, runs the table's RLS SELECT policy    │
   │    against the subscriber's auth.uid() / role                │
   │  ─ delivers ONLY rows that pass RLS                          │
   └──────────────────────────────────────────────────────────────┘
          │
          ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ DB — supabase_realtime publication                            │
   │   public.feature_flags     ✓ allow-listed (global broadcast) │
   │   public.<your_table>      ✓ guarded by trigger              │
   │       └─ requires:                                           │
   │            (a) RLS enabled                                   │
   │            (b) >=1 SELECT/ALL policy with USING (...) qual   │
   │            (c) NO SELECT/ALL policy with USING (true)        │
   │       └─ OR row in realtime_publication_allowlist            │
   └──────────────────────────────────────────────────────────────┘
```

The broker is a faithful executor of RLS — but only as faithful as the
RLS we wrote. **A table without restrictive RLS broadcasts every row to
every authenticated subscriber.** The guard (`fn_assert_realtime_…`) +
event trigger (`trg_block_unsafe_realtime_publication`) guarantee that
no `ALTER PUBLICATION supabase_realtime ADD TABLE x` can succeed unless
either (a) `x` has restrictive RLS or (b) `x` is on the allow-list with
a written reason.

## 1.0 Threat model addressed

| Vector                                                              | Mitigation                                                  |
|---------------------------------------------------------------------|-------------------------------------------------------------|
| Atleta A inspects WS, tweaks filter to receive Atleta B wallet CDC  | RLS on `wallets` filters the broker fan-out                 |
| New migration adds `coin_ledger` to publication, forgets RLS        | Event trigger raises `P0009 REALTIME_RLS_VIOLATION` → DDL rolls back |
| Dashboard click adds `swap_orders` to publication, forgets RLS      | Same — event trigger fires for ALL roles incl. `supabase_admin` |
| RLS exists but is `USING (true)` (defensive coding mishap)          | Guard rejects `tautological_select_policy_using_true`       |
| Legitimate global-broadcast table (`feature_flags`)                 | Allow-list row + `reason` justifies the exception           |

**Out of scope.** Tables not in the publication. Logical replication to
warm-standby or external sinks (other publications). The guard is
deliberately scoped to `supabase_realtime` because that is the
publication wired to authenticated end-users.

## 2.0 What runs where

### 2.1 Database

- `public.realtime_publication_allowlist` — table of intentional
  exemptions; `(table_schema, table_name)` PK; `reason` is `NOT NULL`
  with `length(trim(reason)) >= 10` to force meaningful justifications.
  RLS forced; `service_role` only.
- `public.fn_realtime_publication_unsafe_tables(p_publication)` —
  diagnostic. Returns one row per offender with columns
  `(table_schema, table_name, rls_enabled, has_select_pol,
  has_open_pol, reason)`.
- `public.fn_assert_realtime_publication_safe(p_publication)` — RAISES
  `P0009 REALTIME_RLS_VIOLATION` listing every offender.
- `public.fn_realtime_publication_ddl_guard()` — event-trigger handler.
  Inspects `pg_event_trigger_ddl_commands()`; only acts when a
  publication object was touched; then re-asserts safety on
  `supabase_realtime`. Failure rolls the txn back, undoing the ADD.
- `EVENT TRIGGER trg_block_unsafe_realtime_publication` — armed on
  `ddl_command_end` filtered to `ALTER PUBLICATION` /
  `CREATE PUBLICATION` tags.

### 2.2 Test harness

- `tools/test_l02_realtime_rls_guard.ts` — integration suite
  exercising the diagnostic, the assertion, and the event trigger
  via `docker exec ... psql` (zero new Node deps).

  ```bash
  NODE_PATH=portal/node_modules npx tsx tools/test_l02_realtime_rls_guard.ts
  ```

## 3.0 Adding a new table to Realtime — checklist

You want `public.foo` events to fan out to subscribers.

1. **Decide the per-row authorization predicate.**
   - Per-tenant?  `USING (group_id IN (SELECT … FROM coaching_members …))`
   - Per-user?    `USING (user_id = auth.uid())`
   - Global broadcast (rare; usually a config table)? See §4 below.

2. **Migration template** (preferred — keeps everything in one txn):

   ```sql
   BEGIN;
   ALTER TABLE public.foo ENABLE ROW LEVEL SECURITY;
   ALTER TABLE public.foo FORCE ROW LEVEL SECURITY;  -- defence-in-depth
   CREATE POLICY foo_realtime_select
     ON public.foo
     FOR SELECT TO authenticated
     USING (user_id = auth.uid());
   ALTER PUBLICATION supabase_realtime ADD TABLE public.foo;
   COMMIT;
   ```

   If the policy is missing or `USING (true)`, the `ALTER PUBLICATION`
   raises `P0009 REALTIME_RLS_VIOLATION` and the entire txn rolls back.
   You'll get a hint pointing here.

3. **Verify locally.**

   ```sql
   SELECT * FROM public.fn_realtime_publication_unsafe_tables();
   -- expect zero rows

   SELECT public.fn_assert_realtime_publication_safe();
   -- expect: NOTICE-free void
   ```

4. **Test cross-tenant from two browser tabs / two test users.** The
   broker is the source of truth — even with the guard green, an
   incorrect predicate can still leak. The guard validates _shape_
   (RLS exists, qualifier is non-trivial), not _correctness_ of the
   predicate itself.

## 4.0 Allow-listing a global-broadcast table

Some tables MUST broadcast to every authenticated client (e.g.
`feature_flags` for L18-06 invalidation, marketplace-style ticker
boards). For those, RLS would be wrong — the broadcast is the design.

```sql
INSERT INTO public.realtime_publication_allowlist
  (table_schema, table_name, reason)
VALUES
  ('public', 'foo',
   'foo is a global config table; clients listen for invalidation broadcasts. No per-user filtering applies.');

ALTER PUBLICATION supabase_realtime ADD TABLE public.foo;
```

Code reviewers should treat allow-list additions like adding a row to
`security_exceptions`: PR description must justify the exemption and
link the audit finding (`L02-08`).

## 5.0 Triage — `P0009 REALTIME_RLS_VIOLATION` during a migration

Symptom: psql / supabase migration apply errors with:

```
ERROR:  REALTIME_RLS_VIOLATION: 1 table(s) in publication supabase_realtime
        lack restrictive RLS — public.foo (rls_disabled)
HINT:   Each offender must either (a) have RLS enabled with at least one
        SELECT policy whose USING expression is not NULL/true, or (b) be
        added to public.realtime_publication_allowlist with a written
        reason. See docs/runbooks/REALTIME_RLS_RUNBOOK.md.
```

| `reason` value                              | What to do                                                                |
|---------------------------------------------|---------------------------------------------------------------------------|
| `rls_disabled`                              | `ALTER TABLE x ENABLE ROW LEVEL SECURITY;` then create a SELECT policy.   |
| `no_select_policy`                          | RLS is on but no policy exists — create one before re-running the ADD.    |
| `tautological_select_policy_using_true`     | Drop the `USING (true)` policy (or rename + replace with a real predicate). |

If the table is genuinely global-broadcast, allow-list it (see §4).

## 6.0 Triage — table that's already leaking in production

Run the diagnostic against the live DB:

```sql
SELECT * FROM public.fn_realtime_publication_unsafe_tables();
```

Each row is an active leak. Mitigation depends on whether the broadcast
is intentional:

1. **Unintentional.** Either:
   ```sql
   -- Option A: harden RLS in place
   ALTER TABLE public.<t> ENABLE ROW LEVEL SECURITY;
   CREATE POLICY <t>_owner ON public.<t> FOR SELECT TO authenticated
     USING (<predicate>);

   -- Option B: yank from publication immediately, then iterate
   ALTER PUBLICATION supabase_realtime DROP TABLE public.<t>;
   ```
   Option B is the panic-stop — clients lose realtime updates on the
   table but no longer leak. Re-add via §3 once the policy is in place.

2. **Intentional.** Allow-list it (§4). Document in PR.

## 7.0 Why this design

- **Event trigger over a CI lint.** A lint catches errors at PR review
  time; an event trigger catches them at every DDL apply, including
  dashboard clicks and emergency `psql` sessions. The cost is a single
  catalog scan per `ALTER PUBLICATION` — orders of magnitude cheaper
  than the leak it prevents.
- **Deny-by-default with an explicit allow-list.** The opposite design
  (deny only for a curated block-list) is what got us here in the first
  place — every new table inherits "open" until someone notices.
- **Self-test at migration time uses NOTICE, not EXCEPTION.** We do not
  want to break a fresh prod apply if some legacy table is already
  unsafe; we surface it loudly so the operator can act, then the event
  trigger holds the line going forward.
- **Function diagnostic returns rows, assertion raises.** Splitting
  read/write keeps the diagnostic safe to call in a read-only session
  (e.g. the audit dashboard), and the raising wrapper keeps the
  trigger one-liner.
- **Allow-list reason is `NOT NULL` with min length.** Audit-grade
  paper trail: future-you reading the list six months from now should
  understand why each exemption exists without git-blame archeology.
