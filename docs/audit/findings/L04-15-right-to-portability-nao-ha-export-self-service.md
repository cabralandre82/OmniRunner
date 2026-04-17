---
id: L04-15
audit_ref: "4.15"
lens: 4
title: "Right to portability — não há export self-service"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["lgpd", "finance", "edge-function", "ux"]
files: []
correction_type: config
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
# [L04-15] Right to portability — não há export self-service
> **Lente:** 4 — CLO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— LGPD Art. 18, V ("portabilidade dos dados a outro fornecedor"). Não existe endpoint `/api/export/my-data` retornando um ZIP com sessões, wallets, badges em JSON/CSV.
## Correção proposta

— Supabase Edge Function `export-my-data` gera ZIP em `storage/exports/{uid}/{timestamp}.zip`, assinada, válida por 24 h, enviada por email.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[4.15]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 4 — CLO, item 4.15).