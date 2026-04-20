---
id: L21-01
audit_ref: "21.1"
lens: 21
title: "MAX_SPEED_MS = 12.5 m/s invalida velocistas profissionais"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["anti-cheat", "gps", "edge-function", "testing", "personas", "athlete-pro"]
files:
  - supabase/functions/_shared/anti_cheat.ts
  - supabase/functions/verify-session/index.ts
  - supabase/functions/strava-webhook/index.ts
  - supabase/migrations/20260421110000_l21_athlete_anti_cheat_profile.sql
correction_type: process
test_required: true
tests:
  - supabase/functions/_shared/anti_cheat.test.ts
  - tools/test_l21_01_02_anti_cheat_profile.ts
linked_issues: []
linked_prs:
  - "903738c"
owner: unassigned
runbook: docs/runbooks/ANTI_CHEAT_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "Resolved jointly with L21-02 in commit 903738c. Thresholds passam a ser por skill_bracket (beginner/intermediate/advanced/elite) com elite max_speed_ms=15.0 + clamp via teleport 60 m/s."
---
# [L21-01] MAX_SPEED_MS = 12.5 m/s invalida velocistas profissionais
> **Lente:** 21 — Atleta Pro · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/_shared/anti_cheat.ts:59`:

```59:59:supabase/functions/_shared/anti_cheat.ts
const MAX_SPEED_MS = 12.5;            // ~45 km/h
```

Usain Bolt em 100m teve velocidade média de 12,42 m/s e **pico de 12,27 m/s** nas fases finais. Velocistas amadores de clube (sub-11 em 100m) ficam na faixa 10-11 m/s. O limiar 12,5 m/s + `SPEED_VIOLATION_THRESHOLD = 0.1` (10 % dos segmentos) flaga **todo atleta profissional** em sessões de velocidade.
## Risco / Impacto

— Elite não consegue usar o produto. Narrativa "Omni Runner para atletas de ponta" ([21] é o primeiro caso de uso que o usuário pediu) **colapsa**.

## Correção proposta

— Thresholds **dependentes do perfil**:

```typescript
// supabase/functions/_shared/anti_cheat.ts
function getThresholds(athleteProfile: { skill_bracket: string }) {
  const base = { MAX_SPEED_MS: 12.5, /* ... */ };
  if (athleteProfile.skill_bracket === "elite") {
    return { ...base, MAX_SPEED_MS: 13.5, TELEPORT_SPEED_MS: 25.0 };
  }
  return base;
}
```

Ou melhor: remover hard cap de velocidade instantânea. Usar **teleport = 2 pontos > 500 m em < 5 s** (impossível por terra em velocidade humana).

## Teste de regressão

— `anti_cheat.elite_sprints.test.ts`: sessão com splits de 10,5 m/s em 100 m + GPS realista → `is_verified = true`, zero flags.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.1).