---
id: L10-04
audit_ref: "10.4"
lens: 10
title: "Sem WAF explícito"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["security", "portal"]
files:
  - portal/src/lib/security/waf.ts
  - portal/src/lib/security/waf.test.ts
  - portal/src/middleware.ts
  - docs/runbooks/WAF_RUNBOOK.md
  - tools/audit/check-waf.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/security/waf.test.ts
  - tools/audit/check-waf.ts
linked_issues: []
linked_prs:
  - local:78c8268
owner: platform-security
runbook: docs/runbooks/WAF_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Shipped a three-layer WAF posture. L1 Vercel Firewall baseline
  (UA deny-list, webhook geo-fence, platform-admin geo alert,
  auth rate limit) is documented in the runbook. L2 is an
  in-process `portal/src/lib/security/waf.ts` module with a
  curated UA deny-list (14 entries: sqlmap/nikto/nmap/...) and a
  path deny-list (19 entries: /wp-admin, /.env, /.git/config,
  ...), plus an explicit allow-list (`/.well-known/security.txt`)
  so L10-01 is never shadowed. Middleware calls `evaluateWaf`
  BEFORE origin pinning and CSRF, emits `waf.blocked` metric,
  and returns 403 via `tagResponse` so CSP/version headers still
  land. L3 Cloudflare is contingency-only with a DNS-switch
  playbook. 40 unit tests + 46 static invariants enforced via
  `npm run audit:waf`.
---
# [L10-04] Sem WAF explícito
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Vercel fornece edge WAF básico, mas não há regras customizadas (bloquear `User-Agent: sqlmap`, geo-fence Supabase a países operados, limite país × rate).
## Correção proposta

— Vercel Firewall rules: bloquear por IP/country/UA/path + integrar Cloudflare (tier pago) se risco aumentar.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.4).