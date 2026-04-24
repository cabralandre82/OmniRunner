---
id: L13-08
audit_ref: "13.8"
lens: 13
title: "PUBLIC_PREFIXES /challenge/, /invite/ podem colidir com /api/challenge/"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["middleware", "fixed", "duplicate"]
files:
  - portal/src/lib/route-policy.ts
  - portal/src/lib/route-policy.test.ts
correction_type: code
test_required: true
tests:
  - "portal/src/lib/route-policy.test.ts (L01-25/L13-08 block — REJECTS nested admin paths)"
  - "npm run audit:k3-domain-fixes"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L01-25
deferred_to_wave: null
note: |
  K3 batch — closed by the L01-25 fix. PUBLIC_PREFIX_PATTERNS now
  ties each public prefix to a full-path regex, so /challenge/123/admin
  no longer collapses into the public set. Test coverage explicitly
  asserts the rejection ('REJECTS nested admin paths like /challenge/123/admin').
---
# [L13-08] PUBLIC_PREFIXES /challenge/, /invite/ podem colidir com /api/challenge/
> **Lente:** 13 — Middleware · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `pathname.startsWith("/challenge/")` também retorna `true` para `/challenge/123/admin-only-action`? Se existir, admin action vira pública.
## Correção proposta

— Regex explícito `^/challenge/[a-z0-9-]+$` ou `/challenge` SOMENTE GET.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.8).