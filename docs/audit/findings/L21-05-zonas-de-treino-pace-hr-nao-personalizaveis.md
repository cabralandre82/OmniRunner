---
id: L21-05
audit_ref: "21.5"
lens: 21
title: "Zonas de treino (pace/HR) não personalizáveis"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function", "migration", "testing", "personas", "athlete-pro"]
files: []
correction_type: test
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L21-05] Zonas de treino (pace/HR) não personalizáveis
> **Lente:** 21 — Atleta Pro · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Código usa "skill_bracket" (`beginner/intermediate/advanced/elite`) como proxy, mas não há:

- Zonas de pace customizadas (Z1-Z5 Jack Daniels, 7 zonas Coggan)
- Zonas de HR (% HRmax ou % HRR Karvonen)
- Threshold pace (calculado de testes 30 min)
- Critical speed (Jones/Vanhatalo)

Sem zonas, treino de "40 min em Z2 aeróbico" é invisível.
## Correção proposta

—

```sql
CREATE TABLE public.athlete_zones (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  pace_zones jsonb NOT NULL,  -- [{zone: 1, min_sec_km: 360, max_sec_km: 420}, ...]
  hr_zones jsonb NOT NULL,
  lthr_bpm integer,
  threshold_pace_sec_km integer,
  vo2max numeric(4,1),
  updated_at timestamptz DEFAULT now(),
  updated_by text  -- 'athlete_manual' | 'auto_calculated' | 'coach_assigned'
);
```

Edge Function `calculate-zones` infere via percentis das últimas 20 sessões + testes de campo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.5).