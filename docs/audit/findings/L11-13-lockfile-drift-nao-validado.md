---
id: L11-13
audit_ref: "11.13"
lens: 11
title: "Lockfile drift não validado"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["supply-chain", "ci", "fixed"]
files:
  - tools/audit/check-lockfile-drift.ts
  - package.json
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 4d7950b
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — new CI guard `tools/audit/check-lockfile-drift.ts`
  scans every workspace (root + portal) and fails when:
    1. package-lock.json is missing entirely
    2. a dependency listed in package.json has no entry in the
       lockfile (i.e. someone forgot to `npm install`)
    3. a pinned dependency in package.json (no ^/~) does not match
       the version recorded in the lockfile
  Wired via `npm run audit:lockfile-drift` for fast lint and
  reused by `audit:k4-security-fixes`. CI continues to run
  `npm ci --ignore-scripts` (L11-12) for the full check; this
  guard catches drift in 2 s instead of 90 s.
---
# [L11-13] Lockfile drift não validado
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— CI não faz `npm ci --only=production` nem `npm install --frozen-lockfile`. Dev esquece de commitar lockfile atualizado.
## Correção proposta

—

```yaml
- run: npm ci  # falha se lockfile out-of-sync
- run: git diff --exit-code package-lock.json
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[11.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 11 — Supply Chain, item 11.13).