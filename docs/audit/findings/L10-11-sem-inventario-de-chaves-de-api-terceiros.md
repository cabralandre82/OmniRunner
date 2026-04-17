---
id: L10-11
audit_ref: "10.11"
lens: 10
title: "Sem inventário de chaves de API terceiros"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["integration", "observability"]
files:
  - docs/security/SECRETS_INVENTORY.md
correction_type: docs
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
# [L10-11] Sem inventário de chaves de API terceiros
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Strava, TrainingPeaks, Firebase, Stripe, Asaas, MP, Sentry, Upstash — chaves distribuídas em `.env.local`, GitHub Secrets, Vercel. Não há planilha central.
## Correção proposta

— `docs/security/SECRETS_INVENTORY.md` (SEM valores — apenas nome, local, dono, data de rotação).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.11).