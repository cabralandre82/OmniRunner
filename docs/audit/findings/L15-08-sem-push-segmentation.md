---
id: L15-08
audit_ref: "15.8"
lens: 15
title: "Sem push segmentation"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["edge-function"]
files:
  - supabase/functions/send-push
correction_type: process
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
# [L15-08] Sem push segmentation
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/functions/send-push` provavelmente envia broadcast ou user-specific. Sem segmentação por perfil (elites, iniciantes, coach, inativos 30 dias).
## Correção proposta

— Tabela `user_segments` com queries SQL + UI `/platform/marketing/campaigns` para CMO disparar push para segmento.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[15.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 15 — CMO, item 15.8).