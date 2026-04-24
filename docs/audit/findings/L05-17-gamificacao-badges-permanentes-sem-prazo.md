---
id: L05-17
audit_ref: "5.17"
lens: 5
title: "Gamificação: badges permanentes sem prazo"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["gamification", "badges", "fixed"]
files:
  - supabase/migrations/20260421820000_l05_17_badge_expiration.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - supabase/migrations/20260421820000_l05_17_badge_expiration.sql
linked_issues: []
linked_prs:
  - aa816fb
  - 8c62f60
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — badge_awards.valid_until timestamptz NULL (NULL = permanent,
  preserves legacy behavior). CHECK ensures valid_until is strictly after
  unlocked_at_ms when set. New view active_badge_awards filters expired.
  Partial index idx_badge_awards_active speeds the dominant read path.
  Annual/seasonal badges set valid_until to season end.
---
# [L05-17] Gamificação: badges permanentes sem prazo
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `badge_awards` não tem `expires_at`. "Atleta de bronze 2024" continua para sempre.
## Correção proposta

— Opcional: badges anuais têm `valid_until`, expiram automático.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.17).