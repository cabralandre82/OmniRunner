---
id: L16-10
audit_ref: "16.10"
lens: 16
title: "Sem tier \"free trial\" / sandbox para parceiros"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["testing"]
files:
  - docs/integrations/PARTNER_SAAS_TIERING.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: platform+integrations
runbook: docs/integrations/PARTNER_SAAS_TIERING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/integrations/PARTNER_SAAS_TIERING.md`. Decisão:
  sandbox em projeto Supabase separado, modo fake-money explícito,
  API keys com prefixo `or_test_`, dados regenerados semanalmente.
  Free trial 30 dias para tier Pro+. Wave 3.
---
# [L16-10] Sem tier "free trial" / sandbox para parceiros
> **Lente:** 16 — CAO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Integração B2B exige primeiro contrato, risco. Parceiro quer testar antes. Sem ambiente `sandbox.omnirunner.com`.
## Correção proposta

— Supabase project separado para sandbox; API keys com prefix `or_test_`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.10).