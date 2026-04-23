# Groups Nearby — Opt-In Proximity Discovery Runbook (L22-05)

**Finding:** [`L22-05`](../audit/findings/L22-05-grupos-locais-sem-descoberta-por-proximidade.md)
**Owner:** data · mobile
**CI guard:** `npm run audit:groups-nearby`
**Migration:** `supabase/migrations/20260421370000_l22_05_coaching_groups_nearby.sql`
**Tests:** `tools/test_l22_05_coaching_groups_nearby.ts`

---

## 1 · Why this exists

Before L22-05, amateurs (`Lente 22`) could only discover a coaching
group by word-of-mouth or by already knowing its invite code. The audit
called out the missing surface `GET /api/groups/nearby` with an explicit
privacy guard: *"amador aprova compartilhamento de localização
aproximada"*. We needed a nearby-discovery feature **without** exposing
exact training locations (stalker vector) or requiring a PostGIS
dependency just for this one use-case.

## 2 · What shipped (invariants)

| Piece | Location | Responsibility |
|---|---|---|
| `coaching_groups.base_lat / base_lng` | migration | stored at 5-decimal precision, **never** returned raw by any helper |
| `coaching_groups.allow_discovery` | migration | `false` by default; coach flips via `fn_group_set_base_location` |
| `coaching_groups.location_precision_m` | migration | `500 \| 1000 \| 5000` — coach-chosen snap grid |
| `chk_coaching_groups_discovery_needs_coords` | migration | flipping `allow_discovery=true` without coords is a CHECK violation |
| `idx_coaching_groups_discovery_lat` | migration | partial btree used by the bounding-box prune |
| `fn_groups_snap_coord(coord, precision_m)` | migration | IMMUTABLE helper, rounds a WGS84 degree to the precision grid |
| `fn_groups_nearby(lat, lng, radius_km)` | migration | STABLE SECURITY DEFINER; radius clamped to `[1, 100]`, LIMIT 50, returns **snapped** coords only |
| `fn_group_set_base_location(...)` | migration | VOLATILE SECURITY DEFINER; caller MUST equal `coach_user_id` |
| `fn_coaching_groups_assert_discovery_shape()` | migration | raise `P0010` when columns / checks / index / helpers / privileges drift |
| `GET /api/groups/nearby` | `portal/src/app/api/groups/nearby/route.ts` | authenticated-only, validates inputs, calls RPC |
| `check-groups-nearby` | CI guard | calls the shape asserter, filters output for L22-05 markers |

## 3 · Privacy posture

> **The raw lat/lng stored on `coaching_groups` never leaves the
> database.** Every consumer — the RPC, the Next route, and any future
> native client — receives coords already snapped to the coach's chosen
> 500 m / 1 km / 5 km grid. `distance_km_approx` is rounded to the
> nearest integer km (min 1) so that triangulation from three probes
> can at most narrow the group to its precision grid, not below it.

| Field | Stored | Returned | Guardrail |
|---|---|---|---|
| `base_lat`, `base_lng` | 5-decimal (full) | never | `fn_groups_nearby` returns `*_snapped` columns only |
| `allow_discovery` | bool | exposed via `coach-only` UI | CHECK ties it to coords presence |
| `location_precision_m` | smallint | returned alongside snap | CHECK enforces enum |

### Caller privacy

- `GET /api/groups/nearby` requires an authenticated session. Anon
  callers receive `UNAUTHORIZED`.
- The server never persists the caller's supplied `lat`/`lng` —
  they are RPC arguments only.
- Mobile UI MUST ask for location permission before hitting the route
  and SHOULD present a disclosure banner ("compartilhar localização
  aproximada para descobrir grupos") tied to consent event
  (`consent_events.kind = 'groups_discovery'`, follow-up if needed).

## 4 · How to enable discovery for a group (coach workflow)

1. Coach opens `Assessoria → Configurações → Descoberta`.
2. UI asks device permission, drops a pin on the map (coach can nudge
   it ~500 m away from the real trailhead if desired).
3. Coach picks `Precisão` radio: **500 m** (fitness studios), **1 km**
   (running clubs — default), **5 km** (city-scope communities).
4. Toggle `Permitir descoberta` ON.
5. Portal calls `fn_group_set_base_location(group_id, lat, lng,
   precision, true)`.
6. Group appears in `fn_groups_nearby` immediately (index is partial
   btree on `base_lat` — O(log N) lookup).

To pause discovery (e.g. temporary closure, stalker incident), call
the same RPC with `p_allow_discovery := false`. Coords stay stored
(to make re-enabling trivial) but the partial index excludes the row,
so no discovery query can see it.

## 5 · Operational playbooks

### 5.1 `audit:groups-nearby` fails in CI

Look for the marker(s) in the output:

| Marker | Cause | Fix |
|---|---|---|
| `col:base_lat` (or similar) | A migration ALTER'd away a column | Restore via new migration — never edit the original |
| `chk:discovery_needs_coords` | A migration dropped the CHECK | Recreate in new migration, re-validate |
| `idx:discovery_lat` | Index was dropped | `CREATE INDEX CONCURRENTLY` in a new migration |
| `fn:fn_groups_nearby` | Function signature changed | Re-apply canonical signature (do NOT overload) |
| `priv:anon_can_execute_fn_groups_nearby` | `GRANT ... TO anon` was added somewhere | REVOKE in new migration — anon must NOT reach nearby |

### 5.2 Coach reports "my group doesn't show up"

Triage in this order:
1. `approval_status = 'approved'`? (pending groups never surface)
2. `allow_discovery = true`?
3. `base_lat`/`base_lng` populated?
4. `location_precision_m` set?
5. Is the caller's radius large enough? (clamped at 100 km server-side)

Query:

```sql
SELECT id, name, approval_status, allow_discovery,
       base_lat, base_lng, location_precision_m
  FROM public.coaching_groups
  WHERE name ILIKE '%<partial>%';
```

### 5.3 Abuse report — "someone's scraping /api/groups/nearby"

Short-term: add a per-user rate limit on the Next route (reusing
`portal/src/lib/api/rate-limit-key.ts`). Long-term, add a cap on
results-per-viewer-per-day in an `auth_discovery_probes` table
(schema mirror of `auth_login_attempts` from L10-09). Not shipped
here because there is no evidence of abuse yet — instrumentation
first (Sentry breadcrumb with request_id + auth.uid() hash is
already captured via the logger).

### 5.4 Coach wants **exact** coords visible to members

Out of scope for L22-05. The snap lives on the discovery path
deliberately — member-only surfaces (invite code, group home screen)
can ship a separate RPC reading the raw coords with RLS gated on
`coaching_members.group_id = <id>`. Keep that RPC **not** reachable
from anon/`authenticated` scopes outside the membership row.

### 5.5 Need to offer "city-wide" groups (~50 km radius)

The RPC clamp is 100 km, so the feature already supports it. UX
concern: at that radius the UI becomes cluttered. Prefer: (a) show
the top 20 results by proximity; (b) introduce a `category` filter
(follow-up).

### 5.6 Need GIS-style features later (polygon fence, routing)

This is the moment to introduce PostGIS. Open an ADR referencing
L22-05 and:

1. `CREATE EXTENSION postgis;` in a dedicated migration.
2. Add `base_location geography(POINT)` column, backfill from
   `base_lat/base_lng` via `ST_SetSRID(ST_MakePoint(lng, lat), 4326)`.
3. Replace Haversine with `ST_DWithin(base_location, ST_MakePoint(..),
   radius_m)` — drop the bounding-box prune.
4. Preserve `base_lat/base_lng` for one release as fallback; then
   `ALTER TABLE ... DROP COLUMN`.
5. Keep the `*_snapped` public contract — update `fn_groups_snap_coord`
   to operate on `geography` via `ST_SnapToGrid`.

## 6 · Rollback

This migration is **additive**; there is nothing destructive to roll
back. To fully disable the feature:

1. Revert the Next route by removing
   `portal/src/app/api/groups/nearby/route.ts`.
2. Optionally: `UPDATE coaching_groups SET allow_discovery = false;`
   — index drains via the partial predicate.
3. Do **not** drop the columns; coaches may have already configured
   coords and we would lose that state.

## 7 · Cross-references

- **L04-07** — PII redaction. `base_lat/base_lng` are PII-class once
  persisted; the snap + no-raw-return invariant is what keeps them
  from flowing out to discovery clients.
- **L10-07** — zero-trust JWT. `fn_groups_nearby` is gated by
  `authenticated` grant; the Next route goes through the standard
  Supabase Auth cookie verification.
- **L10-09** — credential stuffing. Future abuse monitoring on
  `/groups/nearby` should mirror the `auth_login_attempts` pattern
  when implemented.
- **L19-08** — CHECK constraint naming. All 4 CHECKs follow
  `chk_<table>_<rule>`.
- **L22-04** — group federation (future). Will consume the same
  opt-in lifecycle.
