---
id: L10-11
audit_ref: "10.11"
lens: 10
title: "Sem inventário de chaves de API terceiros"
severity: medium
status: fixed
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
owner: security+platform
runbook: docs/runbooks/SECRET_ROTATION_RUNBOOK.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Inventory ratified in docs/security/SECRETS_INVENTORY.md.
  Lists every secret by name, vendor, location (Vercel env /
  Supabase Vault / 1Password / GitHub Actions secret / EAS
  Secrets / Mobile signing), owner team, rotation cadence
  (30/90/180/annual/never), and blast radius. Covers Payments
  (Stripe/MP/Asaas), Backend infra (Supabase/Upstash),
  Observability (Sentry/Better Uptime), Integrations
  (Strava/TP/Firebase/Mapbox/Resend/Postmark), CI (GitHub PAT/
  Vercel/Expo), Mobile signing (Android keystore, iOS cert).
  Rotation procedure references docs/runbooks/SECRET_ROTATION_RUNBOOK.md.
  Quarterly review.
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