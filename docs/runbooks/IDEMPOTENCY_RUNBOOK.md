# Idempotency Runbook (L18-02)

Operational guide for the unified server-side idempotency layer
introduced in
`supabase/migrations/20260419120000_l18_idempotency_keys_unified.sql`
and consumed via `portal/src/lib/api/idempotency.ts`.

> Audience: backend on-call + platform admins. Read time ~ 8 min.

## When to use this runbook

- A user / partner reports a duplicate withdrawal, double coin emission,
  or any "I retried and got two of X".
- `idempotency_keys` table grows past `~ 1M rows` (suggests the GC
  cron is not running, or TTL is too long).
- The hourly `idempotency-keys-gc` cron job is failing (alert via
  `cron_run_state.last_status='failed'`).
- A client receives `409 IDEMPOTENCY_KEY_CONFLICT` and is confused.
- You're building a NEW route and want to opt into the wrapper.

## Architecture — 30-second recap

```
              ┌─────────────────────┐
client ─────▶ │  withIdempotency()  │ ─┐
  POST /...   │  (portal helper)    │  │  fn_idem_begin →
              └─────────────────────┘  │     'execute'   ──▶ run handler ─▶ fn_idem_finalize
                                       │     'replay'    ──▶ return cached body+status
                                       │     'mismatch'  ──▶ 409
                                       │
                                       ▼
                              public.idempotency_keys
                              (PK ns, actor_id, key)
```

- **Namespace** identifies the call-site (`custody.withdraw`,
  `coins.distribute`, ...). Keys never collide across namespaces.
- **actor_id** binds the key to the authenticated user. Another
  user replaying the same key gets a fresh slot (zero-trust).
- **request_hash** is `sha256(canonical_json(body))`. Same key +
  different hash = `409` BEFORE any mutation.
- **lifecycle**: `claimed → completed` (success) or `claimed →
  released` (early bail). Stale `claimed` rows older than the
  lease (default 60 s) are reclaimable to prevent a crashed worker
  from poisoning the key forever.
- **TTL**: default 24 h. After `expires_at`, GC sweeps the row.
- **GC**: hourly via `pg_cron` (`idempotency-keys-gc`), wrapped in
  `fn_idem_gc_safe` with `cron_run_state` observability (L12-03
  pattern).

## Diagnostics

### "User says they got two withdrawals"

```sql
-- Did the wrapper see both calls?
SELECT key, status, claimed_at, finalized_at, status_code, response_body
  FROM public.idempotency_keys
 WHERE namespace = 'custody.withdraw'
   AND actor_id  = '<USER_UUID>'
 ORDER BY claimed_at DESC
 LIMIT 20;
```

Interpretation:

- **One row, status=completed**: the wrapper served the second call
  from cache. The duplicate is a UI bug or the user is looking at
  two views of the same withdrawal. Pull `withdrawals` table to
  confirm only one row exists with that `id`.
- **Two rows with different keys**: the client did NOT reuse the
  idempotency key. Two distinct intents → both executed by design.
  This is a client bug; tell them to use the same `x-idempotency-key`
  for retries.
- **One row, status=claimed (>60 s ago)**: a worker crashed mid-
  execution. The next retry will reclaim and run again. Check
  `withdrawals` for any half-applied state.

### "Idempotency cron is failing"

```sql
SELECT * FROM public.cron_run_state WHERE name = 'idempotency-keys-gc';
```

Then:

```sql
SELECT count(*) FROM public.idempotency_keys WHERE expires_at < now();
```

If `last_status='failed'` and the count above is large:

1. Manually run the GC: `SELECT public.fn_idem_gc();`
2. Inspect the `last_error`/`last_meta` for the failure cause
   (typical: lock_timeout when concurrent traffic is high — usually
   self-resolves by next hour).
3. If repeated failures: increase `lock_timeout` in `fn_idem_gc`
   from 5 s → 15 s temporarily, OR DELETE in chunks:

   ```sql
   WITH gone AS (
     SELECT ctid FROM public.idempotency_keys
      WHERE expires_at < now() LIMIT 5000 FOR UPDATE SKIP LOCKED
   )
   DELETE FROM public.idempotency_keys k
    WHERE ctid IN (SELECT ctid FROM gone);
   -- repeat until 0 rows affected
   ```

### "Client got 409 IDEMPOTENCY_KEY_CONFLICT"

```sql
SELECT request_hash, status, claimed_at, response_body IS NOT NULL AS has_response
  FROM public.idempotency_keys
 WHERE namespace = '<NS>'
   AND actor_id  = '<USER>'
   AND key       = '<KEY>';
```

The wrapper returns 409 when the same `(namespace, actor_id, key)`
exists with a different `request_hash`. Causes:

- **Client bug**: same key sent twice with subtly different bodies
  (e.g. one with `provider_fee_usd: undefined`, another with `0`).
  Fix: client should generate a fresh UUID per logical request.
- **Replay attack**: someone harvested a key and tries to replay
  with a different body. The 409 is the correct defense; no action
  needed beyond logging.

The client should:
- Generate a new UUID v4 for the new request, OR
- Send the byte-identical original body to replay.

## Mitigation playbooks

### "Wrapper is rejecting valid retries with 409"

Hypothesis: the body canonicalisation is unstable across the
client's two attempts (e.g. property order, default values added
client-side after first attempt).

Verification:

```sql
SELECT request_hash, claimed_at FROM public.idempotency_keys
 WHERE actor_id = '<USER>' AND key = '<KEY>';
```

If the hashes differ, ask the client to log the EXACT body bytes
they sent on each attempt. Likely culprits: ISO timestamps, null
vs. omitted fields, locale-formatted numbers.

If you confirm the bodies are semantically identical but formatted
differently, the temporary fix is to bump the wrapper's TTL on
that route to a small value (e.g. 30 s) so the bad row expires
quickly. Permanent fix: standardise the client serialisation.

### "Disk pressure from idempotency_keys"

The table is partition-friendly but currently flat. If retention
becomes a problem (>10M rows):

- Lower default TTL in `withIdempotency` calls from 24 h → 1 h for
  high-volume routes (mobile pings, webhook acks).
- Lower the per-route TTL via `ttlSeconds` parameter in the wrapper.
- Schedule the GC more often: `cron.alter_job(...)` to `'*/15 * * * *'`.
- Aggressive autovacuum (already set on this table by default; bump
  if needed):
  ```sql
  ALTER TABLE public.idempotency_keys SET (
    autovacuum_vacuum_scale_factor  = 0.05,
    autovacuum_vacuum_threshold     = 1000
  );
  ```

### "Need to opt-out a route from required:true (emergency)"

If `custody.withdraw` is rejecting all traffic because mobile
clients haven't been updated:

1. Hot-fix: edit `portal/src/app/api/custody/withdraw/route.ts`,
   change `required: true` → `required: false`. Deploy.
2. Send the missing-key alert to mobile team via the L13-06 trace
   id channel.
3. Restore `required: true` once mobile rolls.

## Adding the wrapper to a NEW route

```typescript
import { withIdempotency } from "@/lib/api/idempotency";

export async function POST(req: NextRequest) {
  // ... auth, validation, kill switch ...

  return withIdempotency({
    request: req,
    namespace: "domain.action",       // lowercase a-z0-9_./
    actorId: auth.user.id,            // stable identity
    requestBody: parsed.data,         // hashed for mismatch detection
    required: true,                   // mandatory header? (recommended for $$$)
    handler: async () => {
      // Your mutation. Return { status, body, headers? }.
      const result = await doTheThing();
      return { status: 200, body: { ok: true, result } };
    },
  });
}
```

Checklist:
- [ ] Use `lowercase.dotted.namespace`.
- [ ] Pass the AUTHENTICATED user.id as `actorId` (NOT a value
      controlled by the client).
- [ ] Pass the PARSED Zod data as `requestBody`, not the raw body
      (so canonicalisation is consistent).
- [ ] Choose `required: true` for irreversible mutations
      ($, transfers, deletes); `required: false` is fine for
      idempotent-by-construction reads.
- [ ] Add an integration test exercising replay and mismatch.

## Suggested Grafana metrics

(Backed by `cron_run_state` and the table itself; no new
infrastructure needed.)

- `idempotency_keys_total` (gauge) — `SELECT count(*) FROM idempotency_keys`
- `idempotency_keys_expired_total` (gauge) — `... WHERE expires_at < now()`
  (alert if > 50000 — GC is behind)
- `idempotency_gc_last_status` — `cron_run_state.last_status`
- `idempotency_gc_last_deleted` — `cron_run_state.last_meta->>'deleted'`
- `idempotency_replays_per_min` — derive from middleware structured
  logs (`{action: "replay"}`)

## Cross-references

- [L18-02 finding](../audit/findings/L18-02-idempotencia-ad-hoc-em-cada-rpc-padrao-nao.md)
- [Cron health runbook](./CRON_HEALTH_RUNBOOK.md) (L12-03 pattern)
- [Custody runbook](./CUSTODY_INCIDENT_RUNBOOK.md) (consumer of withdraw)
