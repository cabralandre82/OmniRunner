# Push Notification Segmentation Framework

**Status:** Ratified (2026-04-21), implementation Wave 3.
**Owner:** marketing + platform
**Related:** L15-08, L15-06 (A/B testing), L08-09 (event
catalog), `supabase/functions/send-push/`,
L09-09 (consent envelope), L04-03 (consent registry).

## Question being answered

> "`send-push` either broadcasts or targets a single user.
> The CMO can't say 'send this campaign to all athletes who
> haven't logged in for 30 days, on the Pro plan, in the
> South region.' All marketing pushes today are gut-feel
> blasts."

## Decision

**SQL-defined segments + a marketing console at
`/platform/marketing/campaigns`.** No third-party CDP (e.g.
Segment, Iterable, Braze) in v1.

### Segment definition

A `user_segments` table holds a saved segment as a SQL
predicate (DSL — JSONB AST, not free-form SQL):

```sql
CREATE TABLE public.user_segments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  display_name text NOT NULL,
  ast         jsonb NOT NULL,            -- the DSL
  created_by  uuid NOT NULL REFERENCES profiles(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  last_evaluated_at timestamptz,
  last_size   integer
);

-- Eval result snapshot (1 row per segment per eval run)
CREATE TABLE public.user_segment_members (
  segment_id  uuid NOT NULL REFERENCES user_segments(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  added_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (segment_id, user_id)
);
```

### DSL — JSONB AST

```json
{
  "op": "AND",
  "children": [
    { "op": "no_login_for", "days": 30 },
    { "op": "plan_in", "values": ["pro", "elite"] },
    { "op": "region_in", "values": ["BR-S", "BR-SE"] }
  ]
}
```

Operators v1 (12 total):

- Identity: `plan_in`, `region_in`, `coaching_group_in`,
  `role_in`.
- Engagement: `no_login_for`, `last_run_within`,
  `runs_in_last_30d_min`, `streak_min`.
- Lifecycle: `signup_within`, `signup_older_than`,
  `lifecycle_stage_in` (mapped from L08-09 events).
- Logic: `AND`, `OR`, `NOT` (children-of-children).

The DSL is interpreted server-side by
`portal/src/lib/marketing/segment-evaluator.ts` which
generates a single SQL query against materialised views
already in production:

- `mv_user_progression` (engagement signals).
- `profiles` + `coaching_members` (identity).
- `subscription_status` (plan).

No write path runs untrusted SQL — the DSL is enumerated and
type-checked. CI guard `audit:segment-evaluator-coverage`
asserts every operator is in the type checker AND has a
matching test case.

### Evaluation cadence

- **On-demand** when a CMO previews a campaign in the console.
- **Hourly cron** for segments referenced by an active
  recurring campaign (so the segment doesn't lag > 1 h).
- **Lazy** for segments not used in any active campaign (no
  evaluation; saves DB cost).

### Console UI

`/platform/marketing/campaigns`:

- List of saved segments with last eval size + freshness.
- Segment builder: visual tree of the AST + raw JSON view.
- Campaign composer: title + body + deep-link route + when
  to send (now / scheduled / recurring) + segment selector.
- Preview: 5 random users from the segment + their FCM tokens
  + last_login + plan (helps the CMO sanity-check).
- Send: writes a row to `push_campaigns` and enqueues
  individual `send-push` invocations via `pg_net` to respect
  per-user rate limits (max 2 marketing pushes per user per
  week).

### Consent + compliance

- Push opt-in is registered in `consent_grants` with
  `policy_id='marketing_push_v1'`.
- Segments evaluated for marketing campaigns ALWAYS filter
  `WHERE consent_marketing = true` — enforced at the SQL
  level by the segment evaluator, not at the campaign level
  (so a CMO can't accidentally bypass it).
- Transactional pushes (e.g. "championship started") bypass
  this filter — they live on a different namespace
  (`policy_id='product_essential_v1'`, opt-out separately).
- Frequency cap (2/week marketing) is per-user, enforced in
  `send-push` Edge Function via Redis counter
  (key: `marketing_push:{user_id}:{iso_week}`).

### Why no third-party CDP

We considered Iterable, Braze, OneSignal, Customer.io.
Rejected for v1:

1. **Cost.** USD 500-2k/month minimum at our scale.
2. **PII outflow.** All these platforms require shipping
   user attributes to their servers, which is a new LGPD
   data flow + DPA negotiation.
3. **Operational complexity.** A second source of truth for
   "which user is in which segment" creates drift with our
   own analytics warehouse (PostHog + product_events).
4. **What we actually need is composable SQL** against
   already-clean data we own. The console + evaluator
   together are ~ 2 weeks of work; integrating + maintaining
   a CDP is roughly the same and ongoing.

When MAU > 100k or marketing wants templated journey
automation (drip campaigns spanning 7+ touchpoints), we
revisit. Iterable is the front-runner.

## Implementation phasing

| Phase | Scope                                                            | When        |
|-------|------------------------------------------------------------------|-------------|
| 0     | Spec ratified                                                    | 2026-04-21  |
| 1     | `user_segments` table + DSL evaluator + 12 operators             | 2026-Q3     |
| 2     | `/platform/marketing/campaigns` console + recurring eval cron     | 2026-Q3     |
| 3     | Frequency cap + consent filter at SQL level + `audit:segment-evaluator-coverage` | 2026-Q4 |
| 4     | First 5 production segments + 1 campaign sent                    | 2026-Q4     |
