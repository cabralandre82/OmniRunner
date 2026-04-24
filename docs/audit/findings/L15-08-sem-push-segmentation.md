---
id: L15-08
audit_ref: "15.8"
lens: 15
title: "Sem push segmentation"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["edge-function"]
files:
  - docs/marketing/PUSH_SEGMENTATION_FRAMEWORK.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 32ef899

owner: marketing+platform
runbook: docs/marketing/PUSH_SEGMENTATION_FRAMEWORK.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratificado em `docs/marketing/PUSH_SEGMENTATION_FRAMEWORK.md`.
  Decisão: segmentos definidos em SQL via DSL JSONB AST armazenada em
  `user_segments`, com console de marketing para CMO. Filtro de
  consent (opt-in marketing) é aplicado server-side e não pode ser
  desligado pelo console. Frequency-cap por usuário (max 2 marketing
  pushes/semana). Implementação Wave 3.
---
# [L15-08] Sem push segmentation
> **Lente:** 15 — CMO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
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