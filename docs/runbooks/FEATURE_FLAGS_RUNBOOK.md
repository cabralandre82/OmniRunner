# Feature Flags Runbook (L18-06 + L18-07)

Operational guide for the feature-flag subsystem in
`portal/src/lib/feature-flags.ts`. Covers two related Lente-18 fixes:

- **L18-06** — stratified cache TTL (kill switches refresh in 5s; other
  flags in 60s).
- **L18-07** — SHA-256 user-bucket hash (replaces a biased DJB2-style
  accumulator).

> Audience: backend on-call + admin operators flipping kill switches +
> anyone authoring a new A/B experiment. Read time ~ 5 min.

## Architecture — 30-second recap

```
                 ┌─────────────────────────────────────┐
   route handler │ isFeatureEnabled / isSubsystemEnabled │
                 └─────────────────────────────────────┘
                              │
                              ▼
                  ┌─────────────────────┐
                  │  cachedFlags (Map)  │ ◄──── invalidateFeatureCache()
                  │  lastFetchMs        │       (writer-instance, immediate)
                  └─────────────────────┘
                              │
                  effectiveTtlMs(cache):
                  • any kill_switch?  →  5 s   (KILL_SWITCH_TTL_MS)
                  • otherwise          → 60 s   (TTL_MS)
                              │
                              ▼
                    SELECT … FROM feature_flags
```

- The cache is **per-process** (per Vercel serverless instance). Writer
  instances see toggles immediately via `invalidateFeatureCache()`.
  Reader instances on the OTHER end of the fleet see them after the TTL
  window — bounded to 5s for kill switches.
- The **bucket function** `userBucket(userId, key)` uses
  `createHash("sha256").update("${userId}:${key}").digest()` and reads
  the first 4 bytes as a `uint32` mod 100. Sync, deterministic, ~10µs.

## When to use this runbook

- An admin flipped a kill switch and asks **"why isn't it propagating?"**
- An A/B experiment shows **uneven population sizes** when you expected
  a clean 90/10 split.
- You're authoring a new kill switch / A/B flag and need the conventions.
- You're diagnosing a feature-flag-related test failure or DB load spike.

## Diagnostics

### Is the cache stratifying correctly?

Verify in code (read-only):

```bash
rg -n "KILL_SWITCH_TTL_MS|effectiveTtlMs|category === \"kill_switch\"" \
   portal/src/lib/feature-flags.ts
```

Expected: `KILL_SWITCH_TTL_MS = 5_000`, `TTL_MS = 60_000`,
`effectiveTtlMs()` scans the cache and returns the short TTL when any
flag has `category='kill_switch'`.

### Is a flag actually a kill switch in the DB?

```sql
SELECT key, enabled, rollout_pct, category, scope, updated_at, reason
  FROM public.feature_flags
 WHERE category = 'kill_switch'
 ORDER BY key;
```

If a flag you expect to be a kill switch shows `category='product'` or
NULL, the stratified TTL will NOT apply to it — it will sit on the 60s
TTL. Re-categorise:

```sql
UPDATE public.feature_flags
   SET category = 'kill_switch',
       reason   = 'recategorise: subsystem kill switch (INC-XXXX)',
       updated_by = '<your auth.uid>',
       updated_at = now()
 WHERE key = '<KEY>' AND scope = 'global';
```

### Is the bucket distribution actually uniform?

For a flag with `rollout_pct = N`, the expected fraction of `true`
returns is `N/100`. Sanity-check on a sample of real users:

```sql
-- Top 10000 most-recent users
WITH sample AS (
  SELECT id::text AS user_id
    FROM auth.users
   ORDER BY created_at DESC
   LIMIT 10000
)
SELECT user_id FROM sample;
```

Then in a Node REPL with `feature-flags.ts`:

```ts
import { __test_userBucket } from "@/lib/feature-flags";
const inBucket = users.filter(u => __test_userBucket(u, "MY_KEY") < 10).length;
console.log({ expected: 1000, observed: inBucket });
// Expect ~1000 ± 60 for a 10% rollout on 10000 users (3-sigma band).
```

If the observed count is wildly off (> 3-sigma), file a ticket — it's
either a bug in the new SHA-256 implementation or a non-random user-id
generator upstream.

## Common scenarios

### Scenario 1 — operator flipped a kill switch but instance X still serves traffic for it

**Symptom**: admin disabled `swap.enabled`. Within 5s most instances
respect the toggle, but one or two outlier requests slip through.

**Cause**: a serverless instance is INSIDE its 5s window; the next read
will refresh.

**Mitigation**: wait 5s. If a kill switch absolutely cannot tolerate
5s of slip, escalate to:

1. Set `rollout_pct = 0` AT THE DB LEVEL (writes a different row, but
   `isSubsystemEnabled` ignores rollout_pct — useless for kill switches).
2. Use a **second layer** at the DB-side: e.g. a check-constraint trigger
   or RPC-level guard that reads `feature_flags` directly with
   `READ COMMITTED` (skips cache entirely; ~1ms cost per call). If this
   is needed for a financial subsystem, raise a Lente-18 follow-up ticket
   to add a server-side fast-path read for that key.

### Scenario 2 — A/B experiment shows lopsided populations after the SHA-256 switch

**Symptom**: an experiment that ran on the old DJB2 hash with rollout
50/50 reports population shifts (e.g. cohort A grew 5%, cohort B
shrank 5%) immediately after the L18-07 deploy.

**Cause**: this is **expected**. SHA-256 produces unbiased buckets but
maps users to DIFFERENT buckets than DJB2. Every running A/B is
implicitly re-randomised on the deploy day.

**Mitigation**:

1. Mark the experiment "paused" in your tracking sheet on the deploy
   date. Don't compare cohorts straddling the cutover.
2. For experiments measuring cumulative metrics (LTV, retention),
   either restart with a fresh `key` suffix (e.g. `MY_FEATURE_v2`) or
   accept the discontinuity and segment your analysis pre/post-cutover.
3. For pure A/A health checks, no action needed.

### Scenario 3 — `feature_flags` DB load spiked after the L18-06 deploy

**Symptom**: `pg_stat_statements` shows `SELECT … FROM feature_flags`
QPS jumped (e.g. from 1/s to 10/s).

**Cause**: expected — kill switches now refresh every 5s instead of
every 60s. The table is single-digit rows so the absolute load is
negligible (microseconds per query, no index needed beyond the PK).

**Mitigation**: only intervene if `feature_flags`-related queries
account for > 1% of DB CPU sustained. If so, options in order of
preference:

1. Increase `KILL_SWITCH_TTL_MS` to 10s — halves the read rate while
   still meeting "fast" propagation.
2. Move kill switches to Vercel Edge Config (key-value with
   sub-second propagation), keeping `feature_flags` for product
   toggles only. This is a Lente-18 follow-up, not an emergency lever.

## Adding a new flag

### A new product / experimental flag (60s TTL)

```sql
INSERT INTO public.feature_flags
  (key, enabled, rollout_pct, category, scope, reason, updated_by)
VALUES
  ('beta_dashboard_v3', true, 10, 'product', 'global',
   'Initial 10% rollout to internal users', '<your auth.uid>');
```

Calling code:

```ts
import { isFeatureEnabled } from "@/lib/feature-flags";

if (await isFeatureEnabled("beta_dashboard_v3", session.userId)) {
  return <NewDashboard />;
}
```

### A new kill switch (5s TTL)

```sql
INSERT INTO public.feature_flags
  (key, enabled, rollout_pct, category, scope, reason, updated_by)
VALUES
  ('payouts.batch_v2.enabled', true, 100, 'kill_switch', 'global',
   'Subsystem kill switch for batch payout v2 rollout', '<your auth.uid>');
```

Calling code (route handler):

```ts
import { assertSubsystemEnabled, FeatureDisabledError } from "@/lib/feature-flags";

try {
  await assertSubsystemEnabled("payouts.batch_v2.enabled");
} catch (e) {
  if (e instanceof FeatureDisabledError) {
    return NextResponse.json(
      { error: "Subsystem temporarily disabled", code: e.code },
      { status: 503, headers: { "Retry-After": "30" } },
    );
  }
  throw e;
}
```

The `category='kill_switch'` value is what auto-enables the 5s TTL on
the next cache cycle — no code change needed.

## Suggested observability

| Metric                                             | Source                          | Alert threshold       |
| -------------------------------------------------- | ------------------------------- | --------------------- |
| `feature_flag_kill_switch_propagation_seconds`    | synthetic toggle + read probe   | p99 > 8s (warn)       |
| `feature_flag_db_select_qps`                       | `pg_stat_statements`            | > 50/s (investigate)  |
| `feature_flag_userbucket_p99_us`                   | application trace               | > 100µs (warn)        |
| `feature_flag_cache_invalidation_rate`             | log scan: `invalidateFeatureCache` | > 60/min/instance (investigate) |

## Related runbooks

- [Wallet Mutation Guard (L18-01)](./WALLET_MUTATION_GUARD_RUNBOOK.md)
- [Idempotency (L18-02)](./IDEMPOTENCY_RUNBOOK.md)
- [Custody Incident (L06-01)](./CUSTODY_INCIDENT_RUNBOOK.md)
