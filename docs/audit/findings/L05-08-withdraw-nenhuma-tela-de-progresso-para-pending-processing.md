---
id: L05-08
audit_ref: "5.8"
lens: 5
title: "Withdraw: nenhuma tela de progresso para pending→processing→completed"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "mobile", "portal", "cron", "reliability"]
files:
  - portal/src/app/api/custody/withdraw/route.ts
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
# [L05-08] Withdraw: nenhuma tela de progresso para pending→processing→completed
> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/custody/withdraw/route.ts` cria o withdraw e executa imediatamente. Para gateways assíncronos (PIX fim de semana), status fica em `processing` sem UI mostrando. Como [2.3], não há handler do callback.
## Risco / Impacto

— Admin fica sem feedback ("o dinheiro saiu ou não?") → abre ticket no suporte → custo operacional.

## Correção proposta

—

1. Trocar `execute_withdrawal` para retornar `{"status": "processing", "provider_ref": "..."}`.
2. Webhook do gateway atualiza para `completed|failed`.
3. Portal exibe timeline com 4 estados e "estimativa 10 min" / "estorno em até D+2 se falhar".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.8).