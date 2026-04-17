---
id: L11-10
audit_ref: "11.10"
lens: 11
title: "actions/checkout@v4 SHA não pinned"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["portal", "migration"]
files:
  - .github/workflows/portal.yml
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L11-10] actions/checkout@v4 SHA não pinned
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `.github/workflows/portal.yml:34,52,...` usa tag `@v4` ao invés de commit hash. Tag pode ser movida por atacante que comprometa a org.
## Correção proposta

— Pinar por commit SHA:

```yaml
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
```

Automatizado via `pinact` ou `renovate` config.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.10).