# Connection Pooling — Operational Runbook

> **Audit ref:** L19-09
> **Owner:** Platform / DBA
> **Last reviewed:** 2026-04-23

This runbook documents how the Omni Runner stack acquires
PostgreSQL connections, what pool modes are configured, and how
to react when burst traffic exhausts capacity.

---

## 1. Topology

```
┌────────────────┐       ┌──────────────────┐       ┌──────────────┐
│ Vercel portal  │──────▶│  Supabase pgBouncer │────▶│  Postgres   │
│ (Edge & SSR)   │       │  (transaction mode) │      │  (primary)  │
└────────────────┘       └──────────────────┘       └──────────────┘

┌────────────────┐       ┌──────────────────┐
│ Edge Functions │──────▶│  Supabase pgBouncer │
│ (Deno runtime) │       │  (transaction mode) │
└────────────────┘       └──────────────────┘

┌────────────────┐       ┌──────────────────┐
│ pg_cron jobs   │──────▶│  Direct primary   │
│ (in-database)  │       │  (no pooler)      │
└────────────────┘       └──────────────────┘
```

- **Portal SSR / Edge** → pooler in **transaction mode**, host
  `aws-0-<region>.pooler.supabase.com:6543`. Created lazily via
  `@supabase/ssr` per request; client objects do **not** persist
  across requests but the underlying TCP socket is multiplexed by
  pgBouncer.
- **Edge Functions** → same pooler, also transaction mode.
  `createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)` per
  invocation; underlying socket pooled.
- **pg_cron** → executes inside Postgres; no pooler, no socket.

---

## 2. Pool sizes

| Tier | Pool size | Rationale |
|---|---|---|
| Supabase Free            |   60 conns shared | dev only |
| Supabase Pro             |  200 conns shared | staging |
| Supabase Team            |  400 conns shared | prod (current) |
| Supabase Enterprise      | 1000 conns shared | prod (after Wave 3) |

The pgBouncer **default_pool_size** = 20 server connections per
DB user. Supabase configures one user per role (`anon`,
`authenticated`, `service_role`). Effective ceiling is therefore
60 server-side connections to Postgres regardless of pool size.

---

## 3. Why **transaction mode** (not session)

- **Transaction mode** releases the server connection at every
  `COMMIT`. Allows hundreds of clients to share ~20 server
  connections.
- **Session mode** holds a server connection for the entire
  session. Required for `LISTEN/NOTIFY`, prepared statements,
  advisory locks tied to session, temporary tables.

Omni Runner relies **exclusively** on transaction mode because:

- We do not use session-scoped advisory locks (we use
  `pg_try_advisory_xact_lock`).
- All prepared statements are scoped to the transaction.
- We use `pg_listen` only inside pg_cron, not from app code.

If anyone ever introduces session-only features (SET ROLE
persistence, prepared statements across multiple txns), they
**must** add an ADR documenting why and route those connections
to a separate session-mode pool — never silently break the assumption.

---

## 4. Failure modes & runbook

### 4.1 "remaining connection slots are reserved" (Postgres error)

**Symptom:** all SQL fails with `FATAL: remaining connection
slots are reserved for non-replication superuser connections`.

**Cause:** pool exhausted; usually a long-running query holds a
server connection past `idle_in_transaction_session_timeout`.

**Action:**
1. `SELECT pid, now() - xact_start AS age, query FROM
   pg_stat_activity WHERE state != 'idle' ORDER BY age DESC
   LIMIT 20;`
2. Identify long queries; if any has `age > 60s`,
   `SELECT pg_cancel_backend(pid);`.
3. Check Vercel function logs for retries amplifying the load.
4. If sustained, increase pgBouncer pool to next tier in Supabase
   dashboard. Update §2 above.

### 4.2 Edge Function "ETIMEDOUT" connecting to pooler

**Symptom:** Deno runtime logs `connection timeout` to
`aws-0-*.pooler.supabase.com`.

**Cause:** Vercel cold-start + DNS lookup spike OR Supabase
maintenance window.

**Action:**
1. Confirm Supabase status page.
2. Check `npm run audit:edge-clients` (validates lazy client
   creation).
3. If only one region affected, trigger Vercel redeploy of the
   region.

### 4.3 Burst from `/api/coaching/*/daily-digest`

**Symptom:** 400+ concurrent coaches hitting the digest at 06:00
local time (morning ritual).

**Cause:** L23-02 RPC is `STABLE` and read-only but each call
takes ~150 ms; pool can saturate.

**Action:**
1. Cache the digest response per (group_id, as_of) for 5 minutes
   in Vercel KV.
2. Stagger by `Cache-Control: max-age=120`.
3. If still saturated, add Postgres read replica (Wave 3) and
   route `STABLE` RPCs to it.

---

## 5. Observability

- Supabase dashboard → **Database → Pooler** shows server-side
  utilization.
- Sentry → tag `db.pool_exhausted` triggered when client retries
  > 3 times within 1 second.
- pg_cron job `pg_stat_activity_snapshot` every 5 minutes writes
  to `audit_logs` for trend analysis.

---

## 6. Cross-references

- ADR `docs/adr/007-custody-clearing-model.md` — atomic
  multi-statement transactions used during clearing.
- L02-11 — `createServiceClient` per request (validated by
  `audit:edge-clients`).
- L02-15 — `getRedis()` runtime config (similar lazy pattern).
- L19-10 — autovacuum tuning for hot tables.

---

## 7. Histórico

| Versão | Data | Mudança |
|---|---|---|
| 1.0 | 2026-04-23 | Documento inicial — fecha L19-09. |
