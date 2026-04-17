---
id: L14-03
audit_ref: "14.3"
lens: 14
title: "/api/docs carrega Swagger-UI de unpkg sem SRI"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["mobile", "portal"]
files:
  - portal/src/app/api/docs/route.ts
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
# [L14-03] /api/docs carrega Swagger-UI de unpkg sem SRI
> **Lente:** 14 — Contracts · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/docs/route.ts:29-30`:

```29:30:portal/src/app/api/docs/route.ts
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js" crossorigin></script>
  <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-standalone-preset.js" crossorigin></script>
```
## Correção proposta

—

```html
<script
  src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js"
  integrity="sha384-..."
  crossorigin="anonymous"
></script>
```

Melhor: self-host em `/public/vendor/swagger-ui/...` (download artefatos, commit, imutável).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.3).