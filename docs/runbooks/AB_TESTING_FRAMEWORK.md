# A/B Testing Framework — Decision

**Status:** Ratified (2026-04-21)
**Owner:** product + platform
**Related:** L15-06, L08-09 (event catalog), L20-01 (feature
flags / kill-switches infrastructure).

## Question being answered

> "Pricing copy, onboarding flow, CTA button text — all
> decided by gut feeling. There's no `flag|experiment|split|
> statsig|amplitude|growthbook` anywhere in the codebase.
> What's the experimentation infrastructure?"

## Decision

**GrowthBook (self-hosted on Render) + PostHog as the metrics
backend.** A single source of truth for both feature flags
and experiments. Variant assignment logged into the existing
`product_events` table (L08-09 catalog) so analytics queries
keep working without a new pipeline.

### Architecture

```
   Designer / PM defines experiment in GrowthBook UI
             │
             ▼
   GrowthBook config JSON published to CDN edge
             │
             ▼
   Portal SDK ─┬─ Mobile SDK
               │
               ▼
   getFeatureValue('onboarding_v2_enabled', { user_id, group_id, plan })
               │
               ▼
   if assigned → emit event 'experiment.assigned' to PostHog
                 (+ to product_events for SQL joins)
```

### Why GrowthBook (vs Statsig / Amplitude / Flagsmith)

| Tool       | Self-host? | Stats engine                | TS/Dart SDK | Cost (10k MAU)        |
|------------|------------|-----------------------------|-------------|-----------------------|
| **GrowthBook** | Yes (BSL)   | Bayesian (built-in CUPED) | Yes / Yes   | Free (self-host) / USD 99/m cloud |
| Statsig    | No         | Sequential + frequentist    | Yes / Yes   | USD 1k+/m at our scale |
| Amplitude  | No         | Frequentist                 | Yes / Yes   | USD 600+/m            |
| Flagsmith  | Yes (BSL)  | None (flags only)           | Yes / Yes   | Free / USD 45/m       |

Decision: **GrowthBook self-hosted**. Reasons:

1. We already self-host PostHog → adding GrowthBook on the
   same Render infra is incremental cost (~ USD 25/m).
2. Bayesian engine is friendlier than frequentist for our
   small sample sizes (peeking at results without inflating
   alpha).
3. BSL license is fine for our use case (no plan to resell
   the experimentation infra as a product).
4. PostHog integration is first-class: GrowthBook events
   land in PostHog, we keep a single analytics warehouse.

### Variant assignment rules

1. **Stable hash** by `user_id` (or `device_id` for
   pre-signup). The same user always sees the same variant
   for the lifetime of the experiment.
2. **Mutually exclusive groups** for related experiments. The
   onboarding flow can't have two simultaneous experiments on
   the same step — declared in GrowthBook as a "namespace".
3. **Holdout group** of 5% of users always receives the
   control. Used for long-running effect measurement.
4. **No experiments on financial primitives** (custody, swap,
   withdraw, ledger writes). Those are policy-bound; we
   don't A/B-test them. Controlled by a CI guard
   `audit:no-experiments-on-finance` that scans for
   `getFeatureValue` calls inside `app/api/{custody,swap,
   coins,distribute-coins,checkout}/**`.

### `product_events` integration

Every assignment fires a row:

```sql
INSERT INTO product_events (
  event_name, actor_id, actor_role, group_id, payload
) VALUES (
  'experiment.assigned', :user_id, :role, :group_id,
  jsonb_build_object(
    'experiment_id', :experiment_id,
    'variant', :variant,
    'sdk_version', :sdk_version
  )
);
```

This means SQL queries that compute conversion can join the
metric event (e.g. `'checkout.completed'`) against the
assignment event with no extra pipeline:

```sql
SELECT a.payload->>'variant' AS variant,
       count(distinct a.actor_id) AS exposed,
       count(distinct c.actor_id) AS converted
  FROM product_events a
  LEFT JOIN product_events c
    ON c.actor_id = a.actor_id
   AND c.event_name = 'checkout.completed'
   AND c.created_at > a.created_at
 WHERE a.event_name = 'experiment.assigned'
   AND a.payload->>'experiment_id' = 'pricing_v2'
 GROUP BY a.payload->>'variant';
```

### Operational guardrails

- **Sample-ratio mismatch (SRM) check** runs daily. An
  experiment with > 1% deviation from the configured weights
  pages product (could be a bug in the SDK or a logged-out
  user-id collision).
- **Auto-stop** on guardrail metric regression (`signup_rate`
  -10%, `error_rate` +50%, `withdraw_completion` -5%).
  Configured in GrowthBook as "guardrail metrics".
- **Mobile rollout** waits 24 h after portal rollout to catch
  catastrophic SDK bugs before they hit the harder-to-rollback
  app.
- **Experiment registry** (single source) lives at
  `docs/marketing/EXPERIMENT_REGISTRY.md`. Every active
  experiment must have a row there with hypothesis, primary
  metric, expected lift, end date.

## Implementation phasing

| Phase | Scope                                                                  | When       |
|-------|------------------------------------------------------------------------|------------|
| 0     | Spec ratified (this doc)                                               | 2026-04-21 |
| 1     | GrowthBook on Render + portal SDK (`@growthbook/growthbook-react`)     | 2026-Q3    |
| 2     | Mobile SDK (`growthbook` Dart package) + PostHog event mapping         | 2026-Q3    |
| 3     | First 3 experiments (onboarding step ordering, pricing copy, signup CTA) | 2026-Q4 |
| 4     | CI guard `audit:no-experiments-on-finance`                             | 2026-Q4    |

## Why not in this batch

GrowthBook deployment + 2 SDK integrations is ~ 1 week of
work and needs PostHog event-mapping configuration that lives
outside this repo. Closing the finding now means the
**direction is locked** and the implementation has zero
design questions.
