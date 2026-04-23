---
id: L21-11
audit_ref: "21.11"
lens: 21
title: "Ghost mode não funciona para competições reais"
severity: high
status: wont-fix
wave: 1
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["mobile", "personas", "athlete-pro", "strava-only-scope"]
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
note: |
  **wont-fix (2026-04-21).** `challenge_ghost_provider.dart`
  é runtime de corrida in-app — "correr ao lado" de um
  ghost pressupõe loop tick-a-tick de posição live, o que
  não existe desde a Sprint 25.0.0
  (`docs/ARCHITECTURE.md` §7 — Strava-only). Comparação
  pós-sync (meu 5K × ghost de Berlim 2025) continua
  possível via analytics batch e pode ser um follow-up
  separado; este finding específico (ghost durante o run)
  fica fechado.
---
# [L21-11] Ghost mode não funciona para competições reais
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** 🚫 wont-fix (Sprint 25.0.0 — Strava-only)
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
- `2026-04-21` — **Fechado como `wont-fix`**. Ghost durante o run pressupõe tracking in-app (`docs/ARCHITECTURE.md` §7 — Strava-only). Comparação pós-sync é follow-up separado.