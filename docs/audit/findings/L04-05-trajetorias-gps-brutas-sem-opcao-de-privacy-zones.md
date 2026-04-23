---
id: L04-05
audit_ref: "4.5"
lens: 4
title: "Trajetórias GPS brutas sem opção de privacy zones (home/work zones)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "integration", "mobile", "migration", "testing", "reliability"]
files:
  - supabase/migrations/20260421560000_l04_05_privacy_zones.sql
  - tools/audit/check-privacy-zones.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs:
  - local:b5a4720
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
fixed_at: 2026-04-21
closed_at: 2026-04-21
note: |
  GPS polyline privacy primitives now live server-side (the app
  no longer tracks runs itself — Strava is the single source —
  so enforcement has to happen where the polyline is stored).
  - `profiles.privacy_zones jsonb` with IMMUTABLE shape
    validator (max 5 zones, radius clamped [50, 500] m).
  - Pure helpers: `fn_haversine_m`, `fn_point_in_zones`,
    `fn_decode_polyline`, `fn_encode_polyline_value`,
    `fn_encode_polyline`, `fn_mask_polyline(polyline, zones,
    trim_start_m default 200, trim_end_m default 200)`.
  - Viewer-scoped accessor
    `fn_session_polyline_for_viewer(session_id)` —
    owner + platform_admin get raw; everyone else gets the
    mask with default 200m head/tail trim + owner's
    privacy_zones. platform_admin reads are audit-logged to
    `portal_audit_log` (`session.polyline.admin_view`);
    audit failures are fail-open via RAISE WARNING so they
    never block legitimate admin reads.
  - Self-test block covers validator accept/reject, haversine
    sanity, decoder cardinality on Google's canonical sample,
    encoder round-trip, and zone-filtering edge cases.
  - CI guard `npm run audit:privacy-zones` enforces 44
    invariants.
---
# [L04-05] Trajetórias GPS brutas sem opção de privacy zones (home/work zones)
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Em `sessions` (e `omni_runner/lib/data/datasources/drift_database.dart`), polylines são salvas cruas. Não há mascaramento de primeiros 200 m / últimos 200 m — prática padrão no Strava, Garmin Connect, Nike Run.
## Risco / Impacto

— Corrida de atleta profissional publicada no feed revela endereço residencial. Stalking/doxxing. Litígio civil art. 42 LGPD (responsabilidade solidária).

## Correção proposta

—

```sql
ALTER TABLE profiles ADD COLUMN privacy_zones jsonb DEFAULT '[]';
-- Each zone: { "lat": -23.55, "lng": -46.63, "radius_m": 200 }

-- Function applied when serving polyline to any viewer != owner
CREATE FUNCTION fn_mask_polyline(p_polyline text, p_zones jsonb) RETURNS text AS $$
  -- decode, strip points inside any zone, re-encode
$$ LANGUAGE plpgsql;
```

Client-side (`run_summary_screen.dart`): UI para marcar "casa" / "trabalho" + default de 200 m oculto no começo e fim da corrida (visibilidade "friends").

## Teste de regressão

— `privacy_zones.test.dart`: corrida cruzando zona → visível ao atleta completo, mascarado a terceiros.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.5).