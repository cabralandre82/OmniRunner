---
id: L17-02
audit_ref: "17.2"
lens: 17
title: "5378 linhas em portal/src/lib/*.ts e sem segregação por bounded context"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["architecture", "portal", "bounded-context", "ci-guard"]
files:
  - portal/src/lib/_boundaries/manifest.ts
  - portal/src/lib/_boundaries/index.ts
  - tools/audit/check-portal-bounded-contexts.ts
  - tools/audit/baselines/portal-bounded-contexts-baseline.txt
correction_type: ci-guard
test_required: true
tests:
  - portal/src/lib/_boundaries/manifest.test.ts
  - tools/audit/check-portal-bounded-contexts.ts
linked_issues: []
linked_prs: []
owner: portal-architecture
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Em vez de um refactor big-bang do diretório (risco alto, pouco
  benefício sem equipe maior), L17-02 fixa o problema via
  **manifesto + CI guard + baseline ratchet**:

  1. `portal/src/lib/_boundaries/manifest.ts` — single source of
     truth classificando os 55+ arquivos/subdirs em 9 bounded
     contexts: `financial` (custody/clearing/swap/billing/fx/iof),
     `security` (audit/rate-limit/roles/webhook), `platform`
     (feature-flags/cron/analytics/observability), `infra`
     (api/supabase/cache/logger/openapi), `domain` (pure-domain
     value objects: first-run-onboarding, omnicoin-narrative,
     onboarding-flows, periodization, training-load, offline-sync),
     `integration` (deep-links/og-metadata/product-event-schema),
     `shared` (format/actions/export), `qa`, `boundaries`.

  2. `LAYERING_RULES` define edges permitidas entre contexts:
     - `domain` MUST NOT depender de `infra/financial/security/platform`
       (invariante crítico para módulos pure-domain).
     - `infra` depende só de `shared`.
     - `security ↮ platform` (proíbe fan-out horizontal).
     - `qa` tem acesso global; `integration` não toca infra.

  3. CI guard `audit:portal-bounded-contexts` (tools/audit/
     check-portal-bounded-contexts.ts) enforça:
     - todo arquivo/subdir em portal/src/lib está no manifesto;
     - todo manifest entry existe em disco;
     - nenhum import quebra LAYERING_RULES (via parse de
       `import ... from "./x"` e `@/lib/x`);
     - baseline ratchet em
       `tools/audit/baselines/portal-bounded-contexts-baseline.txt`
       congela débitos preexistentes (4 entradas iniciais), e
       falha tanto em NOVAS violações quanto em entradas do
       baseline já corrigidas (ratchet monotonicamente decrescente).

  4. Testes unitários (16 casos em `manifest.test.ts`) verificam
     unicidade de paths, coerência de BOUNDED_CONTEXTS, auto-import
     reflexivo, ausência de edges domain→infra/financial/security,
     edges qa→* completos.

  Débito congelado no baseline (4 imports cross-layer):
  - `actions.ts` (shared) → `route-policy.ts` + `supabase` (infra)
  - `audit.ts` (security) → `observability` (platform)
  - `openapi/routes/v1-financial.ts` (infra) → `swap.ts` (financial)

  Refactor físico (mover arquivos para subdirs) pode ser feito
  incrementalmente sem mudar o manifesto; a CI guard já garante
  que ninguém adicionará novos cross-imports enquanto isso.
---
# [L17-02] 5378 linhas em portal/src/lib/*.ts e sem segregação por bounded context
> **Lente:** 17 — VP Eng · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Portal / Architecture
**Personas impactadas:** Engenharia (onboarding, code review), Platform (SRE)

## Achado
`portal/src/lib/` contém 45+ arquivos top-level (`custody.ts`, `clearing.ts`, `swap.ts`, `audit.ts`, `cache.ts`, `csrf.ts`, `feature-flags.ts`, etc.) sem subdirs de domínio. Refactor de "custódia" tocava arquivo no mesmo nível de "format", merge-conflicts cresciam conforme o diretório.

## Risco / Impacto
- Projeção 20k+ linhas em 12 meses sem barreiras;
- onboarding lento (sem mental map do layout);
- circular imports invisíveis (nenhum linter vê "security" puxando "platform");
- PRs financeiros inflam diff com arquivos de infra.

## Correção aplicada

Em vez de um refactor big-bang do diretório, adotamos abordagem **manifesto + CI guard + baseline ratchet**:

### 1. Single source of truth (`portal/src/lib/_boundaries/manifest.ts`)
Classifica os 55+ arquivos/subdirs em 9 bounded contexts (`financial`, `security`, `platform`, `infra`, `domain`, `integration`, `shared`, `qa`, `boundaries`) com constantes `BOUNDED_CONTEXTS`, tabela `CONTEXT_MANIFEST` e grafo `LAYERING_RULES`.

### 2. Layering rules (grafo direcionado)
- `domain` MUST NOT depender de `infra/financial/security/platform` — garante pureza de value objects.
- `infra` depende apenas de `shared`.
- `security ↮ platform` (horizontal fan-out proibido).
- `qa` tem acesso global.
- `integration` não toca infra diretamente.

### 3. CI guard (`tools/audit/check-portal-bounded-contexts.ts`)
- enfileira todo arquivo / subdir em portal/src/lib e verifica que cada um está no manifesto;
- verifica que todo manifest entry existe em disco;
- parse `import "@/lib/*"` e `import "./*"` para derivar source/target contexts;
- falha em violações de `LAYERING_RULES`;
- **baseline ratchet** em `tools/audit/baselines/portal-bounded-contexts-baseline.txt` congela 4 débitos preexistentes, permitindo que cada um seja removido gradualmente mas nunca adicionar novos.

### 4. Testes unitários (`manifest.test.ts`, 16 casos)
Validam unicidade, coerência, edges proibidas, reflexividade, cobertura qa→*.

### 5. Refactor físico pode ser feito incrementalmente
Os arquivos podem ser movidos para subdirs (`financial/custody.ts`, etc.) sem mudar o manifesto; a CI guard já garante que ninguém adiciona novos cross-imports durante a migração.

## Teste de regressão
- `npx vitest run src/lib/_boundaries --reporter=default`
- `npm run audit:portal-bounded-contexts`
- Regenerar baseline (se necessário): `UPDATE_BASELINE=1 npm run audit:portal-bounded-contexts`

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.2).
- `2026-04-21` — Fixed via manifesto `portal/src/lib/_boundaries/manifest.ts` + CI guard `audit:portal-bounded-contexts` + baseline ratchet (4 débitos preexistentes congelados). Refactor físico pendente, sem pressa: o guard já previne regressão.
