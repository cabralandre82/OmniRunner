---
id: L17-02
audit_ref: "17.2"
lens: 17
title: "5378 linhas em portal/src/lib/*.ts e sem segregação por bounded context"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "rate-limit", "security-headers", "portal", "migration"]
files: []
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
# [L17-02] 5378 linhas em portal/src/lib/*.ts e sem segregação por bounded context
> **Lente:** 17 — VP Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/lib/` contém 45+ arquivos lado-a-lado: `custody.ts`, `clearing.ts`, `swap.ts`, `audit.ts`, `cache.ts`, `csrf.ts`, `feature-flags.ts`, etc. Sem subdirs de domínio. Refactor de "custódia" toca arquivo no mesmo nível de "format".
## Risco / Impacto

— Conforme cresce (projeção: 20k+ linhas em 12 meses), merge conflicts multiplicam, onboarding de novos devs fica lento, circular imports aparecem.

## Correção proposta

— Reorganizar em bounded contexts:

```
portal/src/lib/
├── financial/      # custody, clearing, swap, withdrawal
│   ├── custody.ts
│   ├── clearing.ts
│   ├── swap.ts
│   └── index.ts    # barrel
├── security/       # csrf, rate-limit, audit, webhook
├── platform/       # feature-flags, roles, metrics
├── infra/          # supabase, redis, logger, cache
└── shared/         # format, schemas (cross-context)
```

Migration gradual: renomear um contexto por sprint, atualizar imports via codemod (`jscodeshift`).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.2).