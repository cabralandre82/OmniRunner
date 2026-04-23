---
id: L16-01
audit_ref: "16.1"
lens: 16
title: "Sem white-label / branding customizado por grupo"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal", "migration"]
files:
  - supabase/migrations/20260421590000_l16_01_white_label_branding.sql
  - tools/audit/check-white-label-branding.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-white-label-branding.ts
linked_issues: []
linked_prs:
  - "local:837ce91"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in 837ce91 (J26). Expanded `public.portal_branding` with
  `brand_name`, `subtitle`, `logo_url_dark`, `favicon_url`,
  `branding_enabled`, `updated_by`, `version`. Added
  `fn_validate_hex_color` + `fn_validate_https_url` (IMMUTABLE
  PARALLEL SAFE) and strict CHECK constraints. `BEFORE UPDATE`
  trigger bumps `version`, stamps `updated_by = auth.uid()`, and
  fail-open audits via `portal_audit_log`. `fn_group_branding_public`
  is STABLE SECURITY DEFINER so the login screen can resolve
  branding pre-auth; `fn_group_branding_set` requires
  `coaching_members.role IN ('admin_master','coach')`. Invariants
  locked by `npm run audit:white-label-branding`.
---
# [L16-01] Sem white-label / branding customizado por grupo
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/branding/` existe mas auditoria rápida sugere mínimo. Grupo grande (ex.: "Corredores do Morumbi" com 3000 atletas) quer app com cor/logo próprios no mobile.
## Correção proposta

— `ALTER TABLE coaching_groups ADD COLUMN branding jsonb` com `{primary_color, logo_url, custom_domain}`. Flutter lê via `group_details` endpoint e aplica no ThemeData. Portal aplica via CSS var.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.1).