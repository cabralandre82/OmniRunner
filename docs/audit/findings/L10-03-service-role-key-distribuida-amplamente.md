---
id: L10-03
audit_ref: "10.3"
lens: 10
title: "Service-role key distribuída amplamente"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "edge-function"]
files:
  - portal/src/lib/supabase/service.ts
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L10-03] Service-role key distribuída amplamente
> **Lente:** 10 — CSO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `SUPABASE_SERVICE_ROLE_KEY` aparece em env de:

- 15+ Edge Functions (legítimo)
- `portal/src/lib/supabase/service.ts` e `admin.ts` (legítimo)
- GitHub Actions `portal.yml` (para E2E e k6)
- Provavelmente Vercel prod/preview
## Risco / Impacto

— Uma única key compromete todo o banco. E preview envs de PR também têm acesso a produção.

## Correção proposta

—

1. **Separar keys** prod/staging/preview. GitHub Actions usa `SUPABASE_SERVICE_ROLE_KEY_STAGING`.
2. **Rotação trimestral** com runbook [6.11].
3. **Supabase Vault** + custom roles por caso de uso (ex.: role `billing_role` com grants mínimos).
4. Log de uso do service-role via extensão `pg_audit`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.3).