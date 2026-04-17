---
id: L21-11
audit_ref: "21.11"
lens: 21
title: "Ghost mode não funciona para competições reais"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "personas", "athlete-pro"]
files: []
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
# [L21-11] Ghost mode não funciona para competições reais
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `challenge_ghost_provider.dart` usa comparação relativa sem mostrar coordenadas. Para treino sólo OK. Mas elite quer simular pacing de atleta-rival (ghost de corrida oficial) — sem dados de rival no produto.
## Correção proposta

— Import de splits públicos de competições (IAAF, World Athletics API). "Correr ao lado do tempo do vencedor de Berlim 2025" como desafio.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.11).