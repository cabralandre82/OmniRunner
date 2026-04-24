---
id: L05-12
audit_ref: "5.12"
lens: 5
title: "Challenges sem regras de tie-break"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["challenges", "leaderboard", "fairness", "fixed"]
files:
  - portal/src/lib/challenges/tie-break.ts
  - portal/src/lib/challenges/tie-break.test.ts
  - tools/audit/check-k3-domain-fixes.ts
correction_type: code
test_required: true
tests:
  - "portal/src/lib/challenges/tie-break.test.ts (vitest, deterministic ordering + winner pick)"
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: product
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K3 batch — pure-domain tie-break policy.
  portal/src/lib/challenges/tie-break.ts:
    1) metricValue DESC
    2) totalDurationSeconds ASC      (faster wins)
    3) completedAt ASC               (earliest qualifying time)
    4) athleteUserId ASC             (UUID lexicographic — last resort)
  Exposes compareLeaderboardRows / rankLeaderboard / pickWinner and
  CHALLENGE_TIE_BREAK_SQL_ORDER (for SQL query parity). Closes the
  'first-row-the-DB-returned' bug; ties are now reproducible.
---
# [L05-12] Challenges sem regras de tie-break
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Ao calcular leaderboard de challenge de distância, se dois atletas empatarem, ordem é indeterminada (`ORDER BY total_distance DESC LIMIT 1`). Prêmio vai para quem o DB retornar primeiro.
## Correção proposta

— `ORDER BY total_distance DESC, total_duration_s ASC, created_at ASC` (mais rápido cumprindo ganha). Documentar nas "rules" do challenge.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.12).