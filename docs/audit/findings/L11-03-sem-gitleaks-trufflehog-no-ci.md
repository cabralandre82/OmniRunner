---
id: L11-03
audit_ref: "11.3"
lens: 11
title: "Sem gitleaks / trufflehog no CI"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
files: []
correction_type: config
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
# [L11-03] Sem gitleaks / trufflehog no CI
> **Lente:** 11 — Supply Chain · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— PRs com secret vazado passam direto. Dev pode fazer commit de `SUPABASE_SERVICE_ROLE_KEY=eyJ…` por engano.
## Correção proposta

—

```yaml
- uses: gitleaks/gitleaks-action@v2
  with: { config-path: .gitleaks.toml }
```

+ pre-commit hook `gitleaks protect --staged`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.3).