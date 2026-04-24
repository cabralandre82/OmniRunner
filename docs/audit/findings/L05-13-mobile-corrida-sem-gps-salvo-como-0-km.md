---
id: L05-13
audit_ref: "5.13"
lens: 5
title: "Mobile: corrida sem GPS salvo como 0 km não invalidada"
severity: medium
status: duplicate
wave: 2
discovered_at: 2026-04-17
tags: ["mobile", "reliability"]
files:
  - supabase/migrations/20260421320000_l08_04_sessions_coherence_check.sql
correction_type: migration
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform-data
runbook: docs/runbooks/SESSIONS_COHERENCE_RUNBOOK.md
effort_points: 2
blocked_by: []
duplicate_of: L08-04
deferred_to_wave: null
note: |
  Same root cause as L08-04 — the chk_sessions_coherence constraint
  added in 20260421320000_l08_04_sessions_coherence_check.sql
  rejects total_distance_m < 100 (or moving_ms < 60s) for sessions
  marked verified, which is exactly the invariant the auditor asked
  for here. Mobile (verify-session) and portal (rankings) read the
  same constraint, so closing as duplicate of L08-04.
---
# [L05-13] Mobile: corrida sem GPS salvo como 0 km não invalidada
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/data/datasources/drift_database.dart` aceita `total_distance_m = 0`. Se atleta inicia e fecha sem mover, sessão vale 0 — mas contam para "sessions ativas".
## Correção proposta

— Validar `total_distance_m >= 100` no `submit_session` RPC antes de marcar `status = 3 (verified)`. Sessions < 100 m: status = `4 (invalid)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.13).