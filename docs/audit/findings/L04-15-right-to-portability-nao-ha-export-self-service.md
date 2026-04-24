---
id: L04-15
audit_ref: "4.15"
lens: 4
title: "Right to portability — não há export self-service"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["lgpd", "finance", "edge-function", "ux"]
files:
  - docs/runbooks/DATA_PORTABILITY_EXPORT.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: legal+platform
runbook: docs/runbooks/DATA_PORTABILITY_EXPORT.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: 3
note: |
  Spec ratificada em
  `docs/runbooks/DATA_PORTABILITY_EXPORT.md`. Auto-serviço a
  partir da tela de conta: `POST /api/account/export` enfileira
  via `fn_enqueue_data_export`, cron horário invoca Edge
  Function `export-my-data` com retries (L06-05), grava ZIP em
  `storage/exports/{uid}/{ts}.zip` (cap 500 MB, signed URL 24
  h), notifica via Resend, GC diário apaga após 24 h. Manifest
  + 6 domínios (profile/runs/wallet/coaching/integrations/
  badges). Excluídos por design: dados de outros usuários,
  tokens OAuth (secrets), audit_logs raw, health-data raw
  (opt-in). Rate limit 1/24h por usuário (fail_closed) é a
  própria idempotência. Implementação fica para Wave 3 (Edge
  Function não-trivial + load test + storage GC + email
  templating com revisão legal).
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