# Athlete Monthly Report Runbook

> **Finding:** [L23-11](../audit/findings/L23-11-relatorios-para-atleta-resumo-mensal-do-coach.md)
> **Guard:** `npm run audit:athlete-monthly-report`
> **Runtime guard:** `SELECT public.fn_athlete_monthly_report_assert_shape();`

## 1. Why this exists

Coaches currently hand-write a monthly summary in Google Docs per
athlete (~1h/athlete/month) and send the PDF through WhatsApp. The
*narrative* (highlights, improvements, personal note) is legitimate
coach work and stays human-written. The *data* (volume, sessions,
pace trend, longest run, days active) is what the app already holds
and must auto-fill.

L23-11 ships the **data pipeline**: migration + two RPCs + route +
CI guard + runbook. Rendering the PDF is a deliberate follow-up
(`L23-11-pdf`) so this finding can close without a PDF library
decision bottlenecking it.

## 2. Invariants (CI-enforced)

| # | Invariant | Enforced by |
| - | --------- | ----------- |
| 1 | `coaching_monthly_notes (group_id, user_id, month_start)` is unique | `uq_coaching_monthly_notes` + static guard |
| 2 | `month_start` is quantised to month boundary | `chk_coaching_monthly_notes_month_trunc` + upsert RPC |
| 3 | Free-text fields are bounded at 2048 chars | 3× `chk_coaching_monthly_notes_*_len` + route guard |
| 4 | `fn_athlete_monthly_report` is `SECURITY DEFINER STABLE` | shape guard + static guard |
| 5 | Report RPC double-gates on coach-role AND athlete-in-group | `ATHLETE_NOT_IN_GROUP` branch + static guard |
| 6 | `fn_upsert_monthly_note` is `SECURITY DEFINER VOLATILE` | shape guard |
| 7 | `approved_at` is set iff all three free-text fields are non-empty | upsert RPC + static guard |
| 8 | Route collapses `UNAUTHORIZED` + `ATHLETE_NOT_IN_GROUP` to HTTP 401 | static guard |
| 9 | Runbook cross-links both the CI guard and finding | static guard |

## 3. Response shape

```json
{
  "month_start": "2026-04-01",
  "generated_at_ms": 1745000000000,
  "metrics": {
    "volume_km": 142.37,
    "sessions_count": 16,
    "longest_run_km": 22.10,
    "avg_pace_sec_km": 312.45,
    "avg_bpm": 148.2,
    "days_active": 14,
    "pace_trend_sec_km": -4.10
  },
  "coach_notes": {
    "highlights": "Progrediu no longão, manteve Z2 estável",
    "improvements": "Consistência nos treinos de intervalo",
    "personal_note": "Bom mês. Pronto para subir volume em maio.",
    "approved_at": "2026-04-28T14:00:00Z",
    "updated_at": "2026-04-28T14:00:00Z"
  }
}
```

### Rules inline

- `pace_trend_sec_km` is `second_half_avg − first_half_avg`. **Negative = faster
  in the second half of the month** (improvement). `null` when either half has
  no pace samples.
- `days_active` counts distinct UTC calendar days with ≥1 verified session.
- `avg_pace_sec_km` and `avg_bpm` are `null` if no sessions carried those
  signals — never render as `0 sec/km` or `0 bpm` in the PDF.
- `coach_notes` is `null` until the coach has saved at least once via PUT.
  `approved_at` stays `null` until all three fields are non-empty; use this as
  the "ready to send" flag in the coach UI.

## 4. How-to

### 4.1 Add a new metric (e.g. elevation gain)

1. Extend `month_sessions` CTE in the migration to pull the new column.
2. Add it to the `agg` CTE aggregation.
3. Add a key under `metrics` in the final `jsonb_build_object`.
4. Extend the static guard with a `response RPC surfaces <key>` check.
5. Update §3 response shape in this runbook.
6. Do NOT change existing keys — PDF renderer caches the contract.

### 4.2 Wire the PDF renderer (follow-up L23-11-pdf)

1. New route `POST /api/coaching/athlete-monthly-report/render` accepts
   `{ group_id, user_id, month }`, calls the GET endpoint internally.
2. Renderer consumes the jsonb verbatim — never re-queries sessions.
3. PDF lib choice: `pdfkit` or `@react-pdf/renderer`. Record the choice in
   `docs/adr/NNN-pdf-renderer-for-monthly-report.md`.
4. Store the rendered PDF in `coaching_monthly_reports` (future table),
   not in this notes table.

### 4.3 Add a CSV export

Same shape as §3 flattened; do NOT change jsonb. Add a follow-up route
`GET .../athlete-monthly-report.csv` that reads the jsonb and pivots.

## 5. Operational playbooks

### 5.1 Coach: "metrics look wrong"

1. Capture: `group_id`, `user_id`, month (YYYY-MM), expected value(s).
2. Reproduce with `curl` against the route; confirm metrics jsonb.
3. Diff against raw `sessions` for that athlete in the month window
   (`start_time_ms` falls in `[month_start_ms, next_month_start_ms)` AND
   `is_verified = true`).
4. If sessions are present but missing from the metric: check
   `is_verified` is `true` (unverified sessions are intentionally excluded).
5. If everything matches and coach still disagrees, it's a content
   question ("I think Z2 pace should exclude recoveries") — file a
   follow-up, do NOT tweak `fn_athlete_monthly_report` ad hoc.

### 5.2 Coach sees 401 for their own athlete

Possible causes:

- Caller is NOT `coach` or `assistant` in `coaching_members` for that group.
- `user_id` param does not belong to that `group_id`
  (`ATHLETE_NOT_IN_GROUP` collapsed to 401 on purpose — we do NOT leak
  "the athlete exists but not in this group").
- Session expired — route's own `supabase.auth.getUser()` returned error.

Fix: inspect `coaching_members` for both the caller and the athlete row.

### 5.3 CI guard fails

Read the first `[FAIL]` and branch:

- `migration file present` — migration was renamed/removed. Git revert.
- `coaching_monthly_notes UNIQUE …` — someone removed the unique key;
  DO NOT bypass, the upsert RPC relies on it.
- `fn_athlete_monthly_report is STABLE` — someone changed volatility;
  planner will cache wrongly across repeated dashboard refreshes.
- `route maps UNAUTHORIZED/ATHLETE_NOT_IN_GROUP to 401` — collapsing is a
  privacy invariant, not a UX nicety. Do not "improve" it into a 404.

### 5.4 Runtime shape drift

`P0010 L23-11 DRIFT:<reason>` from infra CI means the live DB diverged
from the migration — usually an out-of-band `CREATE OR REPLACE` in a
hotfix branch. DO NOT bypass. Open an incident, re-apply the migration.

Decoder:

- `function_missing:<name>` — function was dropped.
- `report_wrong_volatility:s_got_v` — STABLE downgraded to VOLATILE.
- `report_not_security_definer` — security downgraded (auth gate is dead).
- `upsert_not_security_definer` — writes are going direct to the table,
  bypassing the coach check. Rotate and re-apply.
- `coaching_monthly_notes_rls_disabled` — RLS disabled by hand. Re-enable.
- `unique_constraint_missing` — upsert will multi-insert. Reapply.

### 5.5 Free-text too long → 400

Route bounds at 2048 chars per field. If a coach hits it, that's a
product issue ("this isn't a free-form essay box"), not a DB issue.
Do not raise the limit ad hoc — change it via `MAX_TEXT_LEN` AND the
three `chk_coaching_monthly_notes_*_len` constraints AND this runbook.

## 6. Detection signals

| Signal | Source | Action |
| ------ | ------ | ------ |
| `[FAIL]` in `npm run audit:athlete-monthly-report` | CI | Block merge |
| `L23-11 DRIFT:*` in psql stderr | infra CI | Incident |
| Route returns 500 `DB_ERROR` in Sentry | prod | §5.4 |
| `/athlete-monthly-report` p95 > 2s | APM | Check `idx_sessions_user_time` (L08-03) |

## 7. Rollback

Fully additive. Rollback = drop the two RPCs + the shape guard + the
table in a reverse migration:

```sql
DROP FUNCTION IF EXISTS public.fn_athlete_monthly_report_assert_shape();
DROP FUNCTION IF EXISTS public.fn_upsert_monthly_note(uuid, uuid, date, text, text, text);
DROP FUNCTION IF EXISTS public.fn_athlete_monthly_report(uuid, uuid, date);
DROP TABLE IF EXISTS public.coaching_monthly_notes;
```

The route file is the second half of rollback (delete folder →
Next.js stops serving it). No cascading breakage: this is a new
surface.

## 8. Cross-references

- **L08-03** — `idx_sessions_user_time` is the dependency that makes
  the monthly scan sub-linear per athlete.
- **L22-05** — same SECURITY DEFINER + shape-guard + static-guard
  pattern (`fn_groups_nearby`).
- **L23-06 / L23-07** — sibling coach surfaces (prescription + group
  triage + athlete triage).
- **L17-03 / L17-05** — `apiUnauthorized`/`apiValidationFailed`/
  `apiError` + logger contract reuse.
- **L04-07** — `coaching_monthly_notes.personal_note` is coach-visible
  PII of a distinct boundary from `coin_ledger.reason`; it is
  intentionally stored here because it is part of the report artefact.
