---
id: L06-10
audit_ref: "6.10"
lens: 6
title: "Não há SLO documentado"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["sre", "slo", "duplicate"]
files:
  - docs/observability/SLO.md
  - observability/slo.yaml
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs:
  - d894bbc
owner: sre
runbook: docs/observability/SLO.md
effort_points: 2
blocked_by: []
duplicate_of: L20-02
deferred_to_wave: null
note: |
  Coberto por L20-02. SLO canônico vive em
  `observability/slo.yaml` (OpenSLO 1.0) com manual operacional
  em `docs/observability/SLO.md` listando SLI/SLO por endpoint
  crítico (custody/withdraw, swap, coaching/digest, etc.). L20-13
  agora liga isto à error budget policy. Nenhum trabalho
  adicional necessário neste finding — fechado como duplicate
  para manter contagem honesta.
---
# [L06-10] Não há SLO documentado
> **Lente:** 6 — COO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed (duplicate of L20-02)

## Correção
Já coberto por L20-02. SLO canônico em `observability/slo.yaml` +
manual em `docs/observability/SLO.md`. Reapontamento para evitar
duplicidade futura: este finding é fechado como `duplicate_of: L20-02`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial.
- `2026-04-23` — Closed as duplicate de L20-02.
