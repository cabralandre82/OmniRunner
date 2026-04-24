---
id: L16-07
audit_ref: "16.7"
lens: 16
title: "TrainingPeaks OAuth client credentials em env"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["integration", "edge-function"]
files:
  - docs/integrations/PARTNER_SAAS_TIERING.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 32ef899

owner: platform+integrations
runbook: docs/integrations/PARTNER_SAAS_TIERING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Consolidado em `docs/integrations/PARTNER_SAAS_TIERING.md`
  (L16-07 + L16-09 + L16-10). Decisão: por tier, contas Business+
  podem registrar suas próprias `client_id/client_secret` em
  `integration_credentials` (encriptados via pgsodium); credenciais
  globais ficam apenas para Starter/Pro. Implementação faseada Wave 3+.
---
# [L16-07] TrainingPeaks OAuth client credentials em env
> **Lente:** 16 — CAO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
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