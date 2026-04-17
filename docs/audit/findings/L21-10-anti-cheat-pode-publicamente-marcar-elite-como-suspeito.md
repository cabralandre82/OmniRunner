---
id: L21-10
audit_ref: "21.10"
lens: 21
title: "Anti-cheat pode publicamente marcar elite como suspeito"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["personas", "athlete-pro"]
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
# [L21-10] Anti-cheat pode publicamente marcar elite como suspeito
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Quando `is_verified = false` por flag, outros atletas podem ver "session not verified" em feed/leaderboard. Atleta profissional com sua integridade em jogo fica exposto a um falso positivo.
## Correção proposta

— Flags só visíveis a `platform_admin` + atleta. Feed mostra "verificação pendente" neutro (sem razão pública). Elite pode solicitar revisão manual antes de virar público.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.10).