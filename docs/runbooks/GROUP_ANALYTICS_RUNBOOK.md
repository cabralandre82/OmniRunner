# Group Analytics Runbook (L23-07)

> **Audience**: coach-product engineers + coaches using the analytics
> endpoint.
> **Linked finding**: [`L23-07`](../audit/findings/L23-07-analise-coletiva-grupo-limitada.md)
> **CI guard**: `npm run audit:group-analytics`
> **Source of truth**:
>   - `supabase/migrations/20260421380000_l23_07_group_analytics_overview.sql`
>   - `portal/src/app/api/platform/analytics/group-overview/route.ts`

---

## 1. Why this exists

`coaching_kpis_daily` was designed to power daily dashboards: it
carries totals per group per day. But coaches doing weekly triage
ask four questions that none of those totals answer alone:

1. **Volume distribution** — who is carrying, who is falling behind?
2. **Overtraining** — who is doing more than prescribed?
3. **Attrition risk** — who stopped showing up?
4. **Collective progress** — are we better or worse than last window?

The finding proposed materialised views. We went with an **on-
demand SECURITY DEFINER RPC** instead because:

- Cardinality is always "one group × 1-2 windows"; there is no
  fan-out that would benefit from pre-aggregation.
- Refresh jobs are operational hazard (stale data, refresh
  deadlocks). On-demand queries lean on the L08-03
  `idx_sessions_user_time` index which is already tuned for the
  exact `user_id + start_time_ms` access pattern.
- Coach triage workflows are interactive — 1-2 queries per visit.

---

## 2. CI invariants

| # | Invariant | Enforced by |
| --- | --- | --- |
| 1 | `fn_group_analytics_overview` exists, is STABLE, SECURITY DEFINER. | `audit:group-analytics` (static) + `fn_group_analytics_assert_shape()` (runtime) |
| 2 | RPC gates on `coaching_members.role IN ('coach','assistant')`. | static guard |
| 3 | RPC raises `UNAUTHORIZED` for non-coach callers. | static guard |
| 4 | `window_days` clamped to `[7, 180]`. | static guard |
| 5 | Response jsonb has all 4 sections. | static guard |
| 6 | `authenticated` role has EXECUTE; public is REVOKEd. | static guard + runtime shape |
| 7 | Portal route gates on `supabase.auth.getUser()`. | static guard |
| 8 | Runbook cross-links guard and finding. | static guard |

Static guard: `npm run audit:group-analytics` (grep-style, no DB
needed).
Runtime guard: `SELECT fn_group_analytics_assert_shape()` raises
`P0010 L23-07 DRIFT:<reason>` on drift.

---

## 3. Response shape

```json
{
  "ok": true,
  "data": {
    "overview": {
      "window_days": 28,
      "generated_at_ms": 1714000000000,
      "volume_distribution": [
        { "user_id": "...", "display_name": "...", "km_window": 120.4, "sessions_window": 12 }
      ],
      "overtraining": [
        { "user_id": "...", "display_name": "...", "km_last7": 45.0, "km_window": 80.0, "ratio": 2.25 }
      ],
      "attrition_risk": [
        { "user_id": "...", "display_name": "...", "sessions_window": 0, "last_session_ms": null }
      ],
      "collective_progress": {
        "total_km_window": 540.2,
        "total_km_prev_window": 412.1,
        "delta_pct": 31.08,
        "active_athletes": 14,
        "total_athletes": 18
      }
    }
  }
}
```

Rules inside the RPC:

- `overtraining` surfaces athletes whose **7-day volume** exceeds
  1.5× their window-normalised weekly mean AND whose last-7d
  volume is ≥ 20 km (the absolute floor — a beginner going from
  2 to 5 km/week should not be flagged).
- `attrition_risk` triggers at either zero sessions in the
  window OR last session > 14 days ago.
- `delta_pct` is `null` when the previous window is empty.

---

## 4. How-to

### 4.1 Change a threshold

- 1.5× overtraining multiplier → edit the `p.km_last7 > 1.5 *`
  clause inside the RPC + update §3 of this runbook + coach
  release note. Bump all thresholds together in a single PR so
  the guard stays green.
- `>= 20 km` floor → same rule; floor is absolute, do not scale
  with window_days.
- `14 days` attrition → same rule; the 14-day number matches the
  audit-wide "dormant athlete" definition and changing it in
  isolation here would diverge from other coach surfaces.

### 4.2 Add a new cut

1. Add a new CTE inside the function.
2. Add it to the final `jsonb_build_object`.
3. Extend the static guard to check the new key in the response.
4. Update this runbook's §3 + §2 table.

### 4.3 Expose a CSV export

- New endpoint `GET /api/platform/analytics/group-overview/export`
  that calls the same RPC and pipes to CSV. Reuse the auth gate.
  Do NOT introduce a second RPC — the underlying computation
  must stay canonical.

---

## 5. Operational playbooks

### 5.1 Coach says "my athletes are missing from volume_distribution"

- Check the athlete is in `coaching_members` with `role = 'athlete'`
  for that group (the RPC filters out coach/assistant rows).
- Check the athlete's sessions have `is_verified = true`.
- Check the athlete has at least 1 session in the requested
  window (the RPC still lists them with `km_window = 0`; if you
  see nothing the athlete was not in `coaching_members`).

### 5.2 Coach says "overtraining flags are wrong"

- Pull the athlete's `sessions` for the last 7 days + the last
  `window_days` days. Recompute `km_last7 / (km_window / (window_days / 7))`.
- If the ratio really is > 1.5 and km_last7 ≥ 20, the RPC is
  right.
- If the coach disagrees with the 1.5× rule for their sport,
  escalate; this is a content change and lives in §4.1.

### 5.3 CI guard fails

- Run `npm run audit:group-analytics` locally.
- Branches:
  - `migration file present` → someone renamed/deleted the
    migration; restore.
  - `fn_group_analytics_overview is SECURITY DEFINER` → someone
    downgraded; restore.
  - `RPC gates on coaching_members role` → authorization was
    stripped; restore immediately and rotate logs.
  - `response jsonb carries "<section>"` → a section was
    dropped from the response; restore before coaches hit stale
    dashboards.

### 5.4 Runtime shape drift

- Infra CI invokes `SELECT fn_group_analytics_assert_shape()`
  every deploy. A `P0010 L23-07 DRIFT:<reason>` means an
  out-of-band migration changed volatility / SECURITY DEFINER /
  grants. Do NOT bypass; open an incident and re-migrate to
  canonical state.

### 5.5 Long query times

- Check that `idx_sessions_user_time` exists (L08-03). Without
  it, the RPC walks `sessions` per athlete per window.
- If it exists and queries are still slow, `window_days > 180`
  was requested — clamp should have caught it; verify.

---

## 6. Detection signals

| Signal | Likely cause | First move |
| --- | --- | --- |
| CI guard red | Migration/route drift | Re-run guard locally, follow §5.3 |
| `P0010 L23-07 DRIFT:*` in logs | Runtime shape drift | §5.4 |
| Route 401 for known coach | `coaching_members` row missing | Verify membership + role |
| Route 500 with `DB_ERROR` | RPC raised unhandled | Check logger/Sentry for the exception |

---

## 7. Rollback

The feature is additive:

- Drop the RPC + the shape guard via a new reverse-migration if
  coaches start relying on the data and the output is wrong in
  a way we cannot hotfix.
- The portal route is pure glue — removing the route file
  returns 404s; no schema left behind.

No dashboards are materialised; nothing to re-seed.

---

## 8. Cross-refs

- `L08-03` — `idx_sessions_user_time` is the index this RPC
  depends on. Without it the per-athlete window scans quadruple.
- `L04-07` — coin_ledger PII guard; the RPC returns
  `display_name` which is already in `coaching_members` and
  considered coach-visible PII, not financial PII.
- `L22-05` — same SECURITY DEFINER + caller-auth gate pattern
  (`fn_groups_nearby`).
- `L23-06` — sibling coach-product surface (periodization
  wizard); together they cover prescription (L23-06) and
  triage (L23-07).
- `L17-03` / `L17-05` — route reuses the `apiError` /
  `apiValidationFailed` / `apiUnauthorized` contract + logger.
