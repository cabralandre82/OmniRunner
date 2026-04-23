---
id: L08-04
audit_ref: "8.4"
lens: 8
title: "Análise de sessions pelo moving_ms mas coluna aceita NULL e 0"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["gps", "portal", "migration"]
files:
  - supabase/migrations/20260312000000_fix_broken_functions.sql
  - supabase/migrations/20260421320000_l08_04_sessions_coherence_check.sql
  - tools/audit/check-sessions-coherence.ts
  - tools/test_l08_04_sessions_coherence_check.ts
  - package.json
  - docs/runbooks/SESSIONS_COHERENCE_RUNBOOK.md
correction_type: migration
test_required: true
tests:
  - tools/test_l08_04_sessions_coherence_check.ts
linked_issues: []
linked_prs:
  - ae57c8c
owner: platform-data
runbook: docs/runbooks/SESSIONS_COHERENCE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L08-04] Análise de sessions pelo moving_ms mas coluna aceita NULL e 0
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** DB
**Personas impactadas:** staff (portal / rankings), mobile (verify-session)
## Achado
— `fn_compute_kpis_batch` faz `SUM(s.moving_ms / 1000.0)`. Sessão com `moving_ms IS NULL` → NULL + X = NULL; `COALESCE(SUM(...), 0)` salva. Mas um session com `moving_ms = 0` & distance > 0 (GPS bug) vira pace infinito em `fn_compute_skill_bracket`:

```103:106:supabase/migrations/20260312000000_fix_broken_functions.sql
      CASE WHEN total_distance_m > 0 AND moving_ms > 0
           THEN (moving_ms / 1000.0) / (total_distance_m / 1000.0)
```

Aqui protege o skill bracket, mas outros queries no portal podem não proteger.
## Correção proposta

— Constraint SQL:

```sql
ALTER TABLE sessions ADD CONSTRAINT chk_sessions_coherence
  CHECK (
    (status < 3) OR
    (total_distance_m = 0 AND moving_ms = 0) OR
    (total_distance_m >= 100 AND moving_ms >= 60000)
  );
```

Sessões "status < 3" (incomplete) livres; sessões finalizadas precisam ter >= 100 m e >= 60 s. Relacionado a [5.13].

## Correção aplicada (2026-04-21)
Migration `20260421320000_l08_04_sessions_coherence_check.sql`:
- Adiciona `chk_sessions_coherence` via `ADD CONSTRAINT NOT VALID + VALIDATE CONSTRAINT`
  (production-friendly; scan local prévio retornou 0 offenders).
- `fn_find_sessions_incoherent(limit)` SECURITY DEFINER classifica offenders
  por `reason` (`gps_zero_moving_ms`, `zero_distance_with_moving`, `distance_below_100m`,
  `moving_below_60s`, `other_incoherent`) para o playbook de backfill.
- `fn_assert_sessions_coherence()` raise P0010 com lista estruturada.
- CI `npm run audit:sessions-coherence`.
- 15 integration tests.
- Runbook [`SESSIONS_COHERENCE_RUNBOOK.md`](../../runbooks/SESSIONS_COHERENCE_RUNBOOK.md).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.4).
- `2026-04-21` — Corrigido (commit `ae57c8c`): CHECK + detector + assert + CI + runbook.