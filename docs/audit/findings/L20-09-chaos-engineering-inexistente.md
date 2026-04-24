---
id: L20-09
audit_ref: "20.9"
lens: 20
title: "Chaos engineering inexistente"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["rate-limit", "mobile", "edge-function", "testing"]
files:
  - docs/runbooks/CHAOS_ENGINEERING.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: sre+platform
runbook: docs/runbooks/CHAOS_ENGINEERING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Runbook ratificado em `docs/runbooks/CHAOS_ENGINEERING.md`.
  Decisão: 6 GameDays/ano (3 staging + 3 prod) com rotação de 6
  cenários cobrindo Redis, Edge, Postgres, Resend, rate-limit e
  Stripe webhook. Sem Gremlin/Chaos Mesh — bash + Vercel CLI são
  suficientes pro escala atual. Pre-flight checklist obriga error-
  budget healthy e on-call ack. Reavalia quando time > 15 eng.
---
# [L20-09] Chaos engineering inexistente
> **Lente:** 20 — SRE · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Nenhum teste de caos (desligar Redis, matar worker, forcar lag DB).
## Correção proposta

— Rodar mensalmente:

- Desabilitar Upstash Redis → confirmar rate-limit degrada graciosamente (mas ver [2.x] sobre fail-open).
- Matar Supabase Edge Function → verificar retries.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[20.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 20 — SRE, item 20.9).