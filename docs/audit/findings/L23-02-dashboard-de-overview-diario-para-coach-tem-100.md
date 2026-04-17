---
id: L23-02
audit_ref: "23.2"
lens: 23
title: "Dashboard de overview diário para coach tem 100-500 atletas"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "reliability", "personas", "coach"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-02] Dashboard de overview diário para coach tem 100-500 atletas
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `coach_insights_screen.dart` existe. Auditoria rápida sugere listagem padrão. Coach com 500 atletas precisa **priorização**:

- Quem **precisa de atenção hoje**: lesão reportada, 3+ dias sem treino, TSS anomaly, plano não cumprido.
- Quem **está indo bem**: pode receber plano mais agressivo.
- Quem **está em PR**: coach felicita pessoalmente.

Sem priorização, coach gasta 3h/dia olhando dashboard manualmente.
## Correção proposta

— `GET /api/coaching/daily-digest?group_id=X` retorna `{needs_attention: [], performing_well: [], at_risk: [], new_prs: []}`. Tela coach é essa lista, não lista alfabética.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.2).