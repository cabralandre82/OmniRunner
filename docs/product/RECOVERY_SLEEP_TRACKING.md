# Recovery & Sleep Tracking — Product Spec

**Status:** Ratified, deferred to Wave 4
**Owner:** Product + mobile
**Related:** L21-13, L21-12 (training load),
L21-19 (active recovery),
L04-04 (health-data consent posture).

## Question being answered

> "Athletes log workouts but not sleep / HRV / readiness.
> Coaches can't suggest a deload week with no data. Garmin/
> Whoop/Oura users have this — we're losing the recovery
> conversation."

## Decision

**Read-only ingestion** of recovery / sleep signals from
existing wearable integrations (Garmin, Polar, Apple Health,
Health Connect). No manual logging UI in v1; manual logging
adds friction and is rarely sustained.

Display a **single derived "readiness" score** (0–100) on the
home screen, with a 7-day trend, plus drill-down to raw
metrics for users who want them.

### What we ingest

| Source            | Sleep duration | Sleep stages | HRV | Resting HR | Body battery / Readiness |
|-------------------|----------------|--------------|-----|------------|--------------------------|
| Garmin Connect    | yes            | yes          | yes | yes        | yes (Body Battery)       |
| Polar Flow        | yes            | yes          | yes | yes        | yes (Nightly Recharge)   |
| Apple HealthKit   | yes            | yes          | yes | yes        | no (synthesize)          |
| Health Connect    | yes            | yes          | yes | yes        | no (synthesize)          |
| Strava            | no             | no           | no  | no         | no                       |

### Schema additions

```sql
create table public.recovery_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  date date not null,                       -- naive date in user's local TZ
  source text not null check (source in ('garmin','polar','apple_health','health_connect','manual')),

  sleep_total_min int,                      -- total sleep
  sleep_deep_min int,
  sleep_rem_min int,
  sleep_light_min int,
  sleep_awake_min int,

  hrv_rmssd_ms numeric,                     -- night-time average
  resting_hr_bpm int,
  body_battery int,                         -- 0-100 if vendor provides
  readiness_score int,                      -- 0-100 if vendor provides

  raw jsonb not null,                       -- vendor payload for debugging
  ingested_at timestamptz not null default now(),

  unique (user_id, date, source)
);

create index recovery_user_date_idx on public.recovery_metrics (user_id, date desc);
```

RLS: `user_id = auth.uid()`. Coaches can read members' rows
through the existing `coaching_members` join policy (L01-26)
when the member has explicitly opted in to share recovery
data with their coach (`coaching_share_recovery boolean`).

### Derived "Omni Readiness" score

When the vendor provides a readiness number, use it.
Otherwise synthesize:

```
omni_readiness = clip(0..100,
    50
  + 0.30 × z(hrv_rmssd_ms,    user_baseline_28d)  × 25
  − 0.30 × z(resting_hr_bpm,  user_baseline_28d)  × 25
  + 0.20 × clip(-1..1, (sleep_total_min − 420) / 120) × 25
  − 0.20 × z(training_load_7d, user_baseline_28d) × 25
)
```

Justification: 28-day rolling baseline so the score is
**personal**, not population-relative; weights borrowed from
the public Stulberg & Magness "polarized recovery" framing,
de-rated to avoid overfitting.

`z(x, baseline)` clipped to `[-2, 2]` to prevent a single bad
night from collapsing the score.

### What we DO NOT do

- No menstrual cycle data integration in this spec — see
  L21-19 for that policy (separate consent surface, separate
  schema).
- No "you should rest today" prescription. We display the
  score; the coach (or user) decides. Avoids medical-device
  classification.
- No coaching nudges based on readiness in v1. Possible v2
  if user feedback is positive.
- No marketing of readiness as a "wellness score" — LGPD
  Art. 11 makes health-purpose-language risky.

### UI surface

- **Home screen**: single ring widget "Readiness 72 / 100"
  with 7-day sparkline.
- **Drill-down screen** ("Recovery"): 28-day chart of HRV,
  resting HR, sleep duration; vendor source badge per row;
  toggle to hide individual metrics.
- **Coach view** (when shared): same drill-down with the
  member's name; redacted if `coaching_share_recovery=false`.

### Privacy / consent

- Recovery data is health data under LGPD Art. 11.
  Ingestion is **off by default** even if the wearable
  integration is connected.
- Opt-in screen: separate from the integration auth screen,
  with explicit text "OmniRunner will read your sleep and
  HRV from <vendor>. You can revoke at any time."
- `consent_registry` row written on opt-in (L04-09).
- Hard-delete on opt-out: drops all `recovery_metrics` rows
  for that user (no soft-delete).

### Why no manual entry in v1

We considered it. Rejected because:

1. Sustained manual sleep logging in fitness apps converges
   to ~ 5% of users after 3 months (Whoop, Oura published
   benchmarks).
2. Manual HRV requires the user owning a chest strap or app —
   if they own those, they have a vendor that can be
   ingested.
3. Adds a UI surface that is mostly maintained for a long
   tail.

Re-evaluate when: > 10k MAU explicitly request manual entry.

### Implementation phases (Wave 4)

1. Schema + RLS + opt-in consent flow.
2. Garmin / Polar adapter (existing OAuth, add new scopes).
3. Apple HealthKit / Health Connect adapter.
4. Readiness derivation function (server-side, runs nightly
   via cron).
5. Mobile home-screen widget + drill-down.
6. Coach share toggle.

## See also

- `docs/policies/HEALTH_DATA_CONSENT.md` (L04-04)
- `docs/integrations/GARMIN_INTEGRATION.md`
- `docs/product/TRAINING_LOAD.md` (L21-12)
