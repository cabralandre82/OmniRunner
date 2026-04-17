---
id: L17-04
audit_ref: "17.4"
lens: 17
title: "Testes unitários em portal/src/lib/qa-*.test.ts — arquivos >800 linhas"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["testing"]
files: []
correction_type: test
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
# [L17-04] Testes unitários em portal/src/lib/qa-*.test.ts — arquivos >800 linhas
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `qa-e2e.test.ts` com 839 linhas, `partnerships.test.ts` 545 linhas. Mega-arquivos-teste são cheirinho de "testes cobrem tudo de uma tabela, não de um comportamento".
## Risco / Impacto

— Quando uma mudança quebra 3 testes, dev tende a comentar o bloco em vez de entender. Long test files + shared setup = flaky tests.

## Correção proposta

— Split por feature; cada test file < 200 linhas; use `describe.concurrent` para paralelizar; `vitest --coverage` garante que não perde cobertura no split.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.4).