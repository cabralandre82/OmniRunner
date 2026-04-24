---
id: L11-10
audit_ref: "11.10"
lens: 11
title: "actions/checkout@v4 SHA não pinned"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["supply-chain", "github-actions", "ci-guard", "baseline-ratchet"]
files:
  - tools/audit/check-actions-pinned.ts
  - tools/audit/baselines/actions-pinned-baseline.txt
correction_type: process
test_required: true
tests:
  - tools/audit/check-actions-pinned.ts
linked_issues: []
linked_prs:
  - d894bbc
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Em vez de pinar 57 actions agora (alta chance de regressão na
  matriz de CI), aplicamos o padrão **baseline ratchet** já usado
  em L17-02/L18-04: CI guard `audit:actions-pinned` enumera todas
  as `uses:` linhas em `.github/workflows/*.yml` e exige SHA de
  40 chars; baseline em `tools/audit/baselines/actions-pinned-
  baseline.txt` lista as 57 entradas legadas (quem repaga a dívida
  remove do baseline). Novas adições FALHAM CI imediatamente.
  Helper para regenerar: `BASELINE_REGEN=1 npx tsx tools/audit/
  check-actions-pinned.ts`. Plano de repagamento: lote por
  workflow file, começando por `security.yml` na Onda 3.
---
# [L11-10] actions/checkout@v4 SHA não pinned
> **Lente:** 11 — Supply Chain · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
CI guard com baseline ratchet. 57 entradas legadas registradas;
qualquer nova `uses:` sem SHA falha o CI imediatamente. Repagar
gradualmente.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Fixed via guard + baseline (57 entries).
