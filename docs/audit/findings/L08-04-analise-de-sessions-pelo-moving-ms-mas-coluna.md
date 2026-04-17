---
id: L08-04
audit_ref: "8.4"
lens: 8
title: "Análise de sessions pelo moving_ms mas coluna aceita NULL e 0"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["gps", "portal", "migration"]
files:
  - supabase/migrations/20260312000000_fix_broken_functions.sql
correction_type: migration
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
# [L08-04] Análise de sessions pelo moving_ms mas coluna aceita NULL e 0
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
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

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.4).