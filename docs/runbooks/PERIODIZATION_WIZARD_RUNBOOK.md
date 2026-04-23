# Periodization Wizard Runbook (L23-06)

> **Audience**: coach-product engineers + coaches auditing the
> wizard output.
> **Linked finding**: [`L23-06`](../audit/findings/L23-06-plano-mensal-trimestral-nao-periodizado.md)
> **CI guard**: `npm run audit:periodization-template`
> **Source of truth**: `portal/src/lib/periodization/`

---

## 1. Why this exists

The `training-plan` module already shipped in April 2026 with a
`cycle_type` column (base/build/peak/recovery/test/free/taper/
transition — see `20260407000000_training_plan_module.sql`) but
**no wizard emitted the blocks**. Coaches had to hand-pick cycle
types for each of the 12-24 weeks of a plan, which does not
scale past a handful of athletes. A coach running 30 athletes in
a meia-maratona block would hand-click 30 × 12 = 360 cycle-type
selections every training cycle.

The fix is pure domain logic + a preview route:

- Coach picks `{raceTarget, totalWeeks, athleteLevel}` in the UI.
- Portal calls `POST /api/training-plan/wizard` and gets a
  `PeriodizationPlan` back.
- Coach edits **blocks** (base/build/peak/taper) — not workouts —
  before materialising them into `training_plan_weeks`.

---

## 2. CI invariants

| # | Invariant | Enforced by |
| --- | --- | --- |
| 1 | 4 race targets (5K, 10K, halfMarathon, marathon) exist. | `audit:periodization-template` |
| 2 | Each race spec has `peakWeeklyKmByLevel` for every athlete level. | `audit:periodization-template` |
| 3 | Each race spec has ascending `min/maxTotalWeeks`. | `audit:periodization-template` |
| 4 | Generator emits base/build/peak/taper blocks. | `audit:periodization-template` |
| 5 | Validator rejects skipped weeks, non-base starts, non-taper ends and non-positive volumes. | `audit:periodization-template` + vitest |
| 6 | Wizard route gates on `supabase.auth.getUser()`. | `audit:periodization-template` |
| 7 | `PeriodizationInputError` maps to `apiValidationFailed` (422). | `audit:periodization-template` |

The guard exits non-zero on any drift.

---

## 3. What shipped

| File | Role |
| --- | --- |
| `portal/src/lib/periodization/types.ts` | Race specs + type aliases. |
| `portal/src/lib/periodization/generate-periodization.ts` | Pure generator + validator. |
| `portal/src/lib/periodization/__tests__/generate-periodization.test.ts` | 21-case vitest suite. |
| `portal/src/app/api/training-plan/wizard/route.ts` | POST preview endpoint. |
| `tools/audit/check-periodization-template.ts` | CI guard (this file). |
| `docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md` | You are here. |

---

## 4. How-to

### 4.1 Add a new race target

1. Edit `types.ts` — append `RaceTarget` union + `RACE_SPECS` entry.
2. Pick `minTotalWeeks` / `maxTotalWeeks` defensively: shorter ranges
   discourage rushed plans; longer ranges have to stay below
   `maxTotalWeeks=28` so the partition math keeps terminating.
3. Populate `peakWeeklyKmByLevel` for all 3 levels — the guard
   rejects partial maps.
4. Run `npx vitest run src/lib/periodization` — the matrix test
   iterates every (target × level × weeks) combination and will
   fail closed if any of them cannot produce a valid plan.
5. Update this runbook's §2 table and ship.

### 4.2 Change a peak volume

- Bump `peakWeeklyKmByLevel.<level>` in `types.ts`.
- Run vitest. The "peak weekly volume equals spec" assertion
  will green as long as the generator keeps reading from the spec.
- Flag it in the PR: coaches who have saved plan names like
  "Meia em 12 semanas (80 km pico)" will see a silent volume
  drift. Add a release note.

### 4.3 Wire the materialiser (follow-up)

The wizard endpoint is preview-only. To persist a plan the coach
calls the existing `/api/training-plan` + `/api/training-plan/
[planId]/weeks` endpoints. The wizard response shape is stable:

```json
{
  "ok": true,
  "data": {
    "plan": {
      "raceTarget": "halfMarathon",
      "totalWeeks": 12,
      "athleteLevel": "intermediate",
      "blocks": [
        {
          "cycleType": "base",
          "weekNumbers": [1, 2, 3, 4, 5],
          "focusText": "...",
          "weeklyVolumeKm": 60,
          "intensityHint": "..."
        }
      ]
    }
  }
}
```

Materialiser should iterate `blocks` and call the bulk-assign RPC
with `cycle_type` = `block.cycleType`.

---

## 5. Operational playbooks

### 5.1 Coach complains "the plan is too easy / too hard"

- Collect `{raceTarget, totalWeeks, athleteLevel}` from the coach.
- Reproduce locally via `generatePeriodization(...)` from a vitest
  scratch file.
- If the peak volume is systematically off for a cohort, the fix
  is a content change in `peakWeeklyKmByLevel` — NOT a per-coach
  override. Collect ≥3 data points before shipping.

### 5.2 Wizard returns 422 "totalWeeks must be between X and Y"

- Expected. The finder tried a timeline outside the race's
  `minTotalWeeks`/`maxTotalWeeks` window (e.g. marathon in 10
  weeks).
- Surface a UI warning explaining the minimum timeline; do NOT
  relax the server-side guard.

### 5.3 CI guard fails

- Run `npm run audit:periodization-template` locally.
- Branches by failure name:
  - `types file present` → confirm `types.ts` was not renamed.
  - `RACE_SPECS declares "<target>"` → a race target was removed;
    either restore it or ship a migration for saved plans.
  - `generator emits "<cycle>" block` → the switch statement was
    broken; restore.
  - `wizard route gates on supabase.auth.getUser()` → someone
    removed the auth check; never ship this unless the endpoint
    also moved behind service-role.

### 5.4 Unit matrix is slow

The full (target × level × weeks) iteration is ~600 plans. It
finishes in < 100 ms because the generator does no I/O. If it
creeps above 1 s, someone added I/O — look for a stray `await` or
`fetch` in `generatePeriodization`.

---

## 6. Detection signals

| Signal | Likely cause | First move |
| --- | --- | --- |
| Guard red on CI | Someone touched types/generator/route without updating guard | Run locally + read failure |
| `audit:verify` still green but route 500s | `PeriodizationInputError` path disabled | Restore `apiValidationFailed` mapping |
| Coaches file tickets "plan starts at peak" | Validator disabled | Restore `assertPeriodizationPlanValid(plan)` at end of generator |

---

## 7. Rollback

The feature is additive: no schema migration, no client wire-up
yet. Reverting the three files in `portal/src/lib/periodization/`
+ the route file + this runbook removes the surface entirely.
Saved training plans already in `training_plans` are unaffected
— they never called the wizard.

---

## 8. Cross-refs

- `L22-05` — same coach persona surface (groups/nearby); both
  ship an auth-gated portal route.
- `L22-06` — reuses `AudioCoachLocale`; the wizard does NOT share
  that vocabulary yet (coach-facing copy is pt-BR only until
  coach locale is formalised).
- `L19-08` — CHECK constraint naming convention; `training_plan_weeks.cycle_type`
  check already follows it (`chk_training_plan_weeks_cycle_type`).
- `L17-05` — logger swallows generator throws via
  `apiError("INTERNAL_ERROR", ...)` instead of leaking stack traces.
