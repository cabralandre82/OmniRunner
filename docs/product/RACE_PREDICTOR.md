# Race Time Predictor — Product Spec

**Status:** Ratified, deferred to Wave 4
**Owner:** Product
**Related:** L21-14, L21-12 (training load),
L21-13 (recovery data).

## Question being answered

> "Athletes ask 'what's my predicted marathon time?' and we
> have all their workouts, but no answer. McMillan / VDOT /
> Riegel are public formulas — why aren't we using them?"

## Decision

Implement a **client-side estimator** with three publicly-
documented models, blended with a fitness-trend adjustment.
Surface the result with **clear caveats** (training-week
quality, last race recency).

## The three models

| Model        | Input            | Strength                      | Weakness                          |
|--------------|------------------|-------------------------------|-----------------------------------|
| **Riegel**   | One race result + new distance | Simple, well-known           | Over-predicts long distances      |
| **VDOT** (Daniels) | One race result        | Validated against US college data | Conservative for ultra distances |
| **McMillan** | One race result        | Includes pace zones for training | Closed formula (we approximate)   |

We implement Riegel and VDOT exactly (public), and an
**approximation** of McMillan with the standard `1.06`
exponent variant.

## Algorithm

```typescript
// All times in seconds, distances in meters.
function riegel(t1: number, d1: number, d2: number): number {
  return t1 * Math.pow(d2 / d1, 1.06);
}

function vdotFromRace(t1: number, d1: number): number {
  // Daniels-Gilbert intermediate.
  // Returns VDOT (a VO2max proxy in his framework).
  const tMin = t1 / 60;
  const v = d1 / tMin;                // m/min
  const pctVo2 = 0.8 + 0.1894393 * Math.exp(-0.012778 * tMin)
                     + 0.2989558 * Math.exp(-0.1932605 * tMin);
  const vo2 = -4.60 + 0.182258 * v + 0.000104 * v * v;
  return vo2 / pctVo2;
}

function timeFromVdot(vdot: number, d: number): number {
  // Inverse: bisect on time until vdotFromRace(t, d) ≈ target.
  let lo = 60, hi = 60 * 60 * 24;
  for (let i = 0; i < 60; i++) {
    const mid = (lo + hi) / 2;
    const v = vdotFromRace(mid, d);
    if (v > vdot) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}
```

The three models produce three estimates. We display:

- The **median** as the headline number ("Predicted: 3:42:18").
- The **min and max** as the uncertainty range
  ("3:38–3:46").
- Each individual model in a "Methodology" expander.

## Fitness adjustment

Pure formulas assume the seed race is current. We adjust by
the fitness trend (chronic training load, L21-12) since the
seed race:

```
adjusted = predicted × (1 + (current_ctl − ctl_at_seed_race) × −0.0008)
```

Where:
- `ctl_at_seed_race` = chronic load on the date of the seed
  race.
- `current_ctl` = chronic load today.
- Coefficient `-0.0008` is calibrated so that a +20-point CTL
  swing moves the prediction by ~ 1.6%, in line with public
  literature on fitness-vs-performance correlation.

Adjustment is **clamped to ± 5%** so a stale CTL signal can't
move the prediction more than a typical day-of-race
variation. If the seed race is older than 90 days, we tag the
prediction as "stale" in the UI.

## Eligible seed races

A workout qualifies as a seed race only if:

1. Tagged `workout_type = 'race'` by the user.
2. Distance is within ± 1% of a standard race distance (5k,
   10k, 15k, half, full, 50k, 100k).
3. The 5-min average pace standard deviation is < 10% of the
   overall average (i.e., it's actually a steady effort, not
   a long run with a sprint at the end).
4. No paused intervals > 30 s (auto-pause heuristic).

If the user has multiple eligible seed races, we pick the
**most recent** within the same season. We do NOT auto-pick
across seasons because the off-season fitness gap is too big.

## What we DO NOT predict

- **Trail / ultra distances > 100 km**. The literature is
  thin and our user base is small. UI shows a "no prediction
  available" state with a link to a forum thread.
- **First-ever distance** with no seed race. UI suggests the
  user run a time-trial (e.g., a 5k tune-up) first.
- **Training pace zones**. McMillan-style zones are out of
  scope here; that's a separate "training pace" feature
  (deferred to a later spec).
- **Race-day weather impact**. The Tipperary heat-correction
  curves are public but adding them invites users to ask
  "what about wind / altitude / hills" and we don't want to
  scope-creep.

## UI surface

```
┌─────────────────────────────────────────┐
│ Race Predictor                          │
│                                         │
│ Based on your 10k on 2026-03-15:        │
│ ┌───────────────────────────────────┐   │
│ │ Marathon       3:42:18 ± 0:04     │   │
│ │ Half           1:48:32 ± 0:02     │   │
│ │ 21k            1:48:32            │   │
│ │ 10 mi          1:21:45            │   │
│ │ 15k            1:16:22            │   │
│ └───────────────────────────────────┘   │
│                                         │
│ ▾ Methodology                           │
│   Riegel:    3:46:01                    │
│   VDOT:      3:42:18                    │
│   McMillan:  3:38:32                    │
│   Fitness adj: −0.4% (CTL +5)           │
│                                         │
│ [Pick a different seed race]            │
└─────────────────────────────────────────┘
```

## Implementation

- **Pure client-side**, no API endpoint. Runs in the mobile
  app and in the portal. No PII leaves the device for the
  prediction itself.
- Seed race query is the only DB read.
- No caching needed (sub-millisecond compute).
- Unit tests against published Riegel/VDOT tables (Daniels'
  book + McMillan's web calculator) — within 1 s of expected
  for marathon distance.

## Why client-side and not server-side

Considered. Rejected:

1. **Privacy**: predictor is not a financial primitive; no
   audit trail needed.
2. **Latency**: instantaneous on device; round-trip would
   add 200 ms for no benefit.
3. **Offline**: works on flights / on-trail / wherever the
   user opens the app.
4. **No training-data lock-in**: any version of the formula
   can be updated by shipping a new client without a
   migration.

## Implementation phases (Wave 4)

1. Pure-function library `omni_runner/lib/features/race_predictor/`
   with unit tests against published tables.
2. Seed-race detection rule.
3. Mobile UI (drawer from the workout detail screen).
4. Portal UI (athlete profile).
5. Localization (pt-BR, en).

## See also

- `docs/product/TRAINING_LOAD.md` (L21-12)
- `docs/product/RECOVERY_SLEEP_TRACKING.md` (L21-13)
