---
id: L11-04
audit_ref: "11.4"
lens: 11
title: "Dependabot agrupa todas as minor+patch — PR monstro"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["testing"]
files:
  - .github/dependabot.yml
correction_type: code
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
# [L11-04] Dependabot agrupa todas as minor+patch — PR monstro
> **Lente:** 11 — Supply Chain · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `.github/dependabot.yml:12-16` faz um único PR com todas minor/patch semanalmente. Se uma quebra, bloqueia todas.
## Correção proposta

— Separar por ecossistema/tópico:

```yaml
groups:
  next-ecosystem:
    patterns: ["next", "next-*", "@next/*"]
  supabase:
    patterns: ["@supabase/*"]
  testing:
    patterns: ["vitest", "@vitest/*", "@testing-library/*", "@playwright/*"]
  other-minor-patch:
    update-types: [minor, patch]
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.4).