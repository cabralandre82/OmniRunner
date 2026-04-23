---
id: L17-04
audit_ref: "17.4"
lens: 17
title: "Testes unitários em portal/src/lib/qa-*.test.ts — arquivos >800 linhas"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["testing", "portal", "refactor"]
files:
  - portal/src/lib/__qa__/qa-e2e-fixtures.ts
  - portal/src/lib/qa-e2e-smoke.test.ts
  - portal/src/lib/qa-e2e-idempotency.test.ts
  - portal/src/lib/qa-e2e-antifraud.test.ts
  - portal/src/lib/qa-e2e-concurrency.test.ts
  - tools/audit/check-portal-test-file-size.ts
  - docs/runbooks/PORTAL_TEST_FILE_SIZE_RUNBOOK.md
correction_type: test
test_required: true
tests:
  - portal/src/lib/qa-e2e-smoke.test.ts
  - portal/src/lib/qa-e2e-idempotency.test.ts
  - portal/src/lib/qa-e2e-antifraud.test.ts
  - portal/src/lib/qa-e2e-concurrency.test.ts
linked_issues: []
linked_prs:
  - "447493a"
owner: portal
runbook: docs/runbooks/PORTAL_TEST_FILE_SIZE_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "2026-04-21 — fixed. qa-e2e.test.ts (842 lines, 4 describes) split into 4 focused files each < 200 lines + a shared __qa__/qa-e2e-fixtures.ts module. 24/24 tests still pass; full portal lib suite: 867 tests across 46 files. CI npm run audit:portal-test-file-size enforces 800-line hard cap + required splits + forbidden monolith + allowlist discipline. Runbook documents the split pattern for future suites."
---
# [L17-04] Testes unitários em portal/src/lib/qa-*.test.ts — arquivos >800 linhas
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
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
- `2026-04-21` — Corrigido. `portal/src/lib/qa-e2e.test.ts` (842 linhas, 24 tests, 4 describes — smoke/idempotency/anti-fraud/concurrency — com ~370 linhas de mock-DB compartilhado no topo) foi split em 4 arquivos focados + 1 módulo de fixtures: `src/lib/__qa__/qa-e2e-fixtures.ts` (402 linhas, fixture module — types `MockAccount`/`MockSettlement`/`MockEvent`/`MockIntent`, objeto `state` exportado mutável, `resetState()`/`resetIntents()`, `handleRpc` dispatcher puro, `mockRpc` `vi.fn()` compartilhado, `rewireMockRpc()` helper, `createIntent`/`consumeIntent`, `makeFromMock(table)` com chainable stubs para `platform_fee_config`/`clearing_events`/`clearing_settlements`/`custody_accounts`) + `qa-e2e-smoke.test.ts` (194 linhas, section 1 com 8 tests), `qa-e2e-idempotency.test.ts` (137 linhas, section 2 com 4 tests), `qa-e2e-antifraud.test.ts` (174 linhas, section 3 com 8 tests), `qa-e2e-concurrency.test.ts` (172 linhas, section 4 com 4 tests). Cada test file invoca `vi.mock('@/lib/supabase/service', ...)` / `@/lib/audit` / `@/lib/custody` inline no top-level (Vitest hoista `vi.mock` per-test-file, não pode ser extraído para o fixture module) apontando para `makeFromMock` e `mockRpc` do módulo compartilhado. `beforeEach` de cada describe chama `resetState()` + `resetIntents()` + `vi.clearAllMocks()` + `rewireMockRpc()`. **Tests**: 24/24 passam (mesmos asserts, mesmo comportamento); full portal lib suite cresce de 43 → 46 files mantendo 867 tests verdes. **CI**: `tools/audit/check-portal-test-file-size.ts` + `npm run audit:portal-test-file-size` — hard cap 800 linhas (todos portal `*.test.ts` sob), soft cap 400 linhas (9 files allowlisted hoje: webhook custody, partnerships, money, schemas, swap/route, clearing, swap, coins.reverse, csrf), required split files exist, `qa-e2e.test.ts` monolítico ausente. **Runbook** `docs/runbooks/PORTAL_TEST_FILE_SIZE_RUNBOOK.md` (~180 linhas): documenta invariant (800 hard / 400 soft), template §4.2 para split (fixtures em `__<feature>__/<feature>-fixtures.ts`, mutable `state` object, `vi.fn()` compartilhado, `rewire<X>()`), detection signals (CI + local wc + vitest duration + PR review), 5 playbooks operacionais (CI falha file > 800, missing split file, monolith back, new file > 400 soft, test runtime regression), rollback posture ("pure refactor, zero runtime impact"), invariants + cross-refs L17-01/L17-03/L17-05. **Escopo deliberadamente excluído**: split de `partnerships.test.ts` (545 linhas, 8 describes, cada < 100 linhas — não viola hard cap, soft cap allowlisted pending "touch it, split it"), `money.test.ts` (639 linhas), `schemas.test.ts` (586 linhas) — todos allowlisted. Follow-ups registrados no runbook §4.3.