---
id: L11-12
audit_ref: "11.12"
lens: 11
title: "npm ci sem --ignore-scripts"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["supply-chain", "github-actions", "ci-guard"]
files:
  - .github/workflows/portal.yml
  - .github/workflows/supabase.yml
  - .github/workflows/security.yml
  - .github/workflows/update-snapshots.yml
  - tools/audit/check-npm-ignore-scripts.ts
correction_type: process
test_required: true
tests:
  - tools/audit/check-npm-ignore-scripts.ts
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Patched todos os 11 `npm ci` em workflows para incluir
  `--ignore-scripts`. CI guard `audit:npm-ignore-scripts` falha
  CI ao primeiro `npm ci` sem o flag. Se algum projeto realmente
  precisar do postinstall (raro), rodar explicitamente via
  `npm run` após o `npm ci --ignore-scripts`.
---
# [L11-12] npm ci sem --ignore-scripts
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
- 11 invocações de `npm ci` em workflows agora usam
  `--ignore-scripts` (portal/supabase/security/update-snapshots).
- CI guard `audit:npm-ignore-scripts` impede regressão.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via patch + CI guard.
