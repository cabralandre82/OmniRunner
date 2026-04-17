---
id: L11-01
audit_ref: "11.1"
lens: 11
title: "CI sem npm audit / flutter pub audit"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "portal", "testing"]
files:
  - .github/workflows/portal.yml
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
# [L11-01] CI sem npm audit / flutter pub audit
> **Lente:** 11 — Supply Chain · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `.github/workflows/portal.yml` rodo lint/test/build/e2e/k6 mas **nenhum passo de security scan**. `flutter.yml` idem.
## Risco / Impacto

— CVE em `next`, `@supabase/ssr`, `zod`, etc. passa despercebido em builds por semanas.

## Correção proposta

—

```yaml
- run: npm audit --production --audit-level=high
  continue-on-error: false   # falhar no build
- uses: snyk/actions/node@master
  with:
    args: --severity-threshold=high --org=omnirunner
  env: { SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }} }

# Flutter
- run: dart pub deps --json > deps.json
- run: npx better-npm-audit # ou pana/osv-scanner
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.1).