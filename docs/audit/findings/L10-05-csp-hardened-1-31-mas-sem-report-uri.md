---
id: L10-05
audit_ref: "10.5"
lens: 10
title: "CSP hardened ([1.31]) mas sem report-uri"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["rls", "security-headers", "portal"]
files: []
correction_type: config
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L10-05] CSP hardened ([1.31]) mas sem report-uri
> **Lente:** 10 — CSO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/next.config.mjs` CSP não tem `report-uri` nem `report-to`. Violações não são detectadas.
## Correção proposta

—

```javascript
Content-Security-Policy-Report-Only ... ; report-to csp-endpoint
Report-To: {"group":"csp-endpoint","max_age":10886400,"endpoints":[{"url":"https://omnirunner.report-uri.com/r/d/csp/enforce"}]}
```

Usar `report-uri.com` ou endpoint interno `/api/csp-report`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.5).