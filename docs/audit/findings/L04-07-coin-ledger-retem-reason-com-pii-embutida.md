---
id: L04-07
audit_ref: "4.7"
lens: 4
title: "coin_ledger retém reason com PII embutida"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity"]
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
# [L04-07] coin_ledger retém reason com PII embutida
> **Lente:** 4 — CLO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `execute_burn_atomic` e várias funções usam `format('Burn of %s coins from %s by user %s', …)`. Se o `%s` inclui nome do atleta ou email (em outras funções), um `SELECT * FROM coin_ledger WHERE user_id = '00...0'` após a anonimização ainda expõe o nome.
## Risco / Impacto

— "Right to be forgotten" parcial.

## Correção proposta

— Revisar todos os `reason` para conter apenas IDs + tipos; ao anonimizar, também fazer:

```sql
UPDATE coin_ledger
SET reason = regexp_replace(reason, 'user \S+', 'user [redacted]')
WHERE user_id = '00000000-0000-0000-0000-000000000000'::uuid;
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.7).