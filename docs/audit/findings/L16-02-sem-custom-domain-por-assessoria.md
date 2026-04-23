---
id: L16-02
audit_ref: "16.2"
lens: 16
title: "Sem custom domain por assessoria"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["mobile", "portal"]
files:
  - supabase/migrations/20260421600000_l16_02_custom_domains.sql
  - tools/audit/check-custom-domains.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-custom-domains.ts
linked_issues: []
linked_prs:
  - "local:2794914"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in 2794914 (J27). Ships server-side primitives for
  host-to-group resolution. `public.coaching_group_domains`
  holds host → group mapping with a state machine
  (pending_dns → verifying → verified → failed/revoked),
  unique host, DNS challenge, and a partial unique index on
  (group_id) WHERE is_primary keeps one primary per group.
  `fn_validate_custom_host` (IMMUTABLE PARALLEL SAFE) rejects
  `omnirunner.*` subdomains, hosts > 253 chars, non-HTTPS
  URLs, IP literals, and hosts without a TLD dot. Normalizer
  trigger lower-cases host/sub on write; audit trigger
  fail-open writes to `portal_audit_log`. Lifecycle RPCs
  (`fn_custom_domain_register` / `_mark_verified` /
  `_mark_failed` / `_revoke`) enforce SoD: admin-only
  register/revoke, service-role-only verify/fail transitions.
  `fn_custom_domain_resolve` is STABLE SECURITY DEFINER so
  Next.js middleware can resolve anon traffic without a row
  leak (only returns verified hosts). Invariants locked by
  `npm run audit:custom-domains`. Edge integration (Vercel
  `/v9/projects/.../domains` + ACME) stays an operational
  wiring task on top of these primitives.
---
# [L16-02] Sem custom domain por assessoria
> **Lente:** 16 — CAO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Todos acessam `portal.omnirunner.app`. Clube grande quer `portal.corredoresmorumbi.com.br`.
## Correção proposta

—

1. `coaching_groups.custom_domain text UNIQUE`.
2. Next.js middleware mapeia Host → group_id.
3. Vercel API: adicionar domain programaticamente via API `POST /v9/projects/.../domains`.
4. Auto-provisionar SSL (Let's Encrypt via Vercel).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[16.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 16 — CAO, item 16.2).