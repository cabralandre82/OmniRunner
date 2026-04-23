---
id: L22-05
audit_ref: "22.5"
lens: 22
title: "Grupos locais sem descoberta por proximidade"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["lgpd", "personas", "athlete-amateur", "geo", "privacy"]
files:
  - supabase/migrations/20260421370000_l22_05_coaching_groups_nearby.sql
  - portal/src/app/api/groups/nearby/route.ts
  - tools/audit/check-groups-nearby.ts
  - tools/test_l22_05_coaching_groups_nearby.ts
  - docs/runbooks/GROUPS_NEARBY_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l22_05_coaching_groups_nearby.ts
  - tools/audit/check-groups-nearby.ts
linked_issues: []
linked_prs:
  - local:32e764f
owner: data-platform
runbook: docs/runbooks/GROUPS_NEARBY_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Delivered an opt-in proximity discovery surface with a
  privacy-preserving snap-to-grid model, without pulling in PostGIS
  (deferred until a second GIS use-case lands):

  1. `coaching_groups` gains `base_lat numeric(8,5)`, `base_lng
     numeric(8,5)`, `allow_discovery boolean NOT NULL DEFAULT
     false`, and `location_precision_m smallint` constrained to
     {500 m, 1 km, 5 km}. Four CHECKs (L19-08 naming) guard
     lat/lng range, precision enum, and forbid enabling
     discovery without coords
     (`chk_coaching_groups_discovery_needs_coords`).
  2. A partial btree index covers only the hot subset
     (`allow_discovery=true AND approval_status='approved' AND
     base_lat IS NOT NULL`) — enough for the bounding-box prune.
  3. `fn_groups_snap_coord(coord, precision_m)` (IMMUTABLE) rounds
     any WGS84 degree to the coach-chosen grid; raw coords never
     leave the database. `fn_groups_nearby(lat, lng, radius_km)`
     (STABLE SECURITY DEFINER, authenticated-only) validates
     inputs (22023 on drift), clamps radius to [1, 100],
     bounding-box-prunes, Haversine-refines, and returns snapped
     coords + distance rounded to the nearest integer km (min 1)
     — defeating triangulation.
  4. `fn_group_set_base_location(...)` (VOLATILE SECURITY
     DEFINER) is the coach's write path: it validates caller =
     `coach_user_id` and toggles discovery only after coords are
     present.
  5. `GET /api/groups/nearby?lat&lng&radius_km` exposes the RPC
     through the canonical `apiOk`/`apiUnauthorized` envelope.
     Unauthenticated requests fail with 401; caller location is
     never persisted.
  6. `fn_coaching_groups_assert_discovery_shape()` raises P0010
     when columns / CHECKs / index / helpers / privileges drift;
     wrapped by `tools/audit/check-groups-nearby.ts` and wired as
     `npm run audit:groups-nearby`.
  7. `tools/test_l22_05_coaching_groups_nearby.ts` (25 cases)
     covers schema, snap, radius, filters, ordering, CHECK
     violations, input validation (22023), and shape-guard drift.
  8. `docs/runbooks/GROUPS_NEARBY_RUNBOOK.md` documents the
     privacy posture, coach enable workflow, 6 operational
     playbooks, rollback posture, and cross-references.

  Code: `32e764f`.
---
# [L22-05] Grupos locais sem descoberta por proximidade
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** data + api
**Personas impactadas:** atleta amador, coach
## Achado
— Amador descobre clube via boca-a-boca. Sem `/groups/nearby` que mostra grupos < 5 km home.
## Correção proposta
— `coaching_groups.base_lat/base_lng (numeric(8,5))` + `allow_discovery`/`location_precision_m`; endpoint `GET /api/groups/nearby?lat&lng&radius_km`. Privacidade por design: snap-to-grid (500 m / 1 km / 5 km) escolhido pelo coach, distância arredondada (min 1 km), coords brutas nunca saem do DB, somente autenticados chamam.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.5).
- `2026-04-21` — ✅ Fixado. Migração 20260421370000, rota `GET /api/groups/nearby`, CI `audit:groups-nearby`, 25 testes de integração verdes, runbook `GROUPS_NEARBY_RUNBOOK.md`. Commit `32e764f`.
