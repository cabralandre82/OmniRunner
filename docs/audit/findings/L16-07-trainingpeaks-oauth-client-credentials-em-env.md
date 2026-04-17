---
id: L16-07
audit_ref: "16.7"
lens: 16
title: "TrainingPeaks OAuth client credentials em env"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["integration", "edge-function"]
files: []
correction_type: code
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
# [L16-07] TrainingPeaks OAuth client credentials em env
> **Lente:** 16 — CAO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Edge Function `trainingpeaks-oauth` usa `TP_CLIENT_ID` / `TP_CLIENT_SECRET`. Compartilhados globalmente — todos os clubes usam a mesma conexão.
## Correção proposta

— Cada clube cria sua própria integração (se tier enterprise). Armazenar credentials encriptados em `integration_credentials` por group_id.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.7).