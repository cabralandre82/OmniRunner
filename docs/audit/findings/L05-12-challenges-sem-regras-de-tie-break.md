---
id: L05-12
audit_ref: "5.12"
lens: 5
title: "Challenges sem regras de tie-break"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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