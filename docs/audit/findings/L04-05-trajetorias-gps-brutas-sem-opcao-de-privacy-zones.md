---
id: L04-05
audit_ref: "4.5"
lens: 4
title: "Trajetórias GPS brutas sem opção de privacy zones (home/work zones)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "integration", "mobile", "migration", "testing", "reliability"]
files:
  - omni_runner/lib/data/datasources/drift_database.dart
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L04-05] Trajetórias GPS brutas sem opção de privacy zones (home/work zones)
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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