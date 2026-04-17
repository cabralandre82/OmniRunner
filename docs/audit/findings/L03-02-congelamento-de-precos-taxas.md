---
id: L03-02
audit_ref: "3.2"
lens: 3
title: "Congelamento de preços / taxas"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "migration", "testing"]
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
# [L03-02] Congelamento de preços / taxas
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Plataforma, Assessoria
## Achado
`execute_burn_atomic` (migration 20260228160001:139-142) lê `rate_pct` de `platform_fee_config` **no momento do burn**, não no momento da emissão das coins.
  - Se a plataforma reduzir `clearing` de 3.0% para 1.0% entre emissão (hoje) e queima (daqui 6 meses), as coins "em trânsito" no ecossistema ganham fee histórico diferente do previsto na hora da emissão.
## Risco / Impacto

Assessorias contestam se taxa sobe inesperadamente. CFO precisa justificar o rate usado em cada settlement.

## Correção proposta

Adicionar `fee_rate_pct_snapshot` em `clearing_settlements` (já existe: `fee_rate_pct` — linha 127 do clearing.ts). Confirmar que é o rate no momento do settle, não da emissão. Se quiser congelar no ato da emissão: adicionar `clearing_fee_rate_pct` em `coin_ledger` e reading ali em vez de `platform_fee_config`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.2).