---
id: L09-07
audit_ref: "9.7"
lens: 9
title: "Política de reembolso/chargeback sem prazo SLA"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function"]
files:
  - supabase/functions/process-refund/
correction_type: docs
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
# [L09-07] Política de reembolso/chargeback sem prazo SLA
> **Lente:** 9 — CRO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Vincula-se a [2.13]. Não há política documentada: "reembolso em até X dias". Código Defesa Consumidor Art. 49 exige 7 dias para arrependimento em vendas remotas.
## Correção proposta

— Implementar `process-refund` Edge Function (já existe em `supabase/functions/process-refund/`) para que deposite reverso + emitir NFS-e de estorno. Configurar SLA: estorno < 48 h úteis.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.7).