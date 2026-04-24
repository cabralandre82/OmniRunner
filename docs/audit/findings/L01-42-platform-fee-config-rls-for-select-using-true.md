---
id: L01-42
audit_ref: "1.42"
lens: 1
title: "platform_fee_config — RLS FOR SELECT USING (true)"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "security-headers", "migration", "rls", "fixed"]
files:
  - supabase/migrations/20260228150001_custody_clearing_model.sql
  - supabase/migrations/20260421760000_l01_42_platform_fee_config_rls.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - "supabase/migrations/20260421760000_l01_42_platform_fee_config_rls.sql (in-migration self-test)"
  - "npm run audit:k2-sql-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — RLS hardening: legacy `USING (true)` policy dropped.
  Replaced with two policies: `read_self_facing` (only fee_type IN
  ('clearing','swap') AND is_active — athletes/coaches see only fees
  that affect them) and `read_admin` (full access for platform_role='admin').
  Maintenance fee row is admin-only. Migration includes pg_policies
  self-test asserting the legacy policy is gone and both new ones exist.
---
# [L01-42] platform_fee_config — RLS FOR SELECT USING (true)
> **Lente:** 1 — CISO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Todos os autenticados
## Achado
`supabase/migrations/20260228150001_custody_clearing_model.sql:27-28` e `20260305100000:17-18` — `USING (true)` permite qualquer autenticado ler **todas as taxas** (incluindo rate_usd de maintenance, fx_spread_pct). Se a plataforma quiser estratégia de pricing diferenciado por grupo, isso vazaria info comercial.
## Risco / Impacto

Baixo hoje (taxas são globais). Alto se modelo evoluir.

## Correção proposta

Ok manter USING(true) por enquanto; documentar no header da migration.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.42]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.42).