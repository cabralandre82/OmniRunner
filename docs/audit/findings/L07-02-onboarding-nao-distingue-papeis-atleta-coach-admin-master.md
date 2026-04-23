---
id: L07-02
audit_ref: "7.2"
lens: 7
title: "Onboarding não distingue papéis (coach, admin_master, assistant)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["portal", "ux", "coach", "onboarding", "personas"]
files:
  - portal/src/lib/onboarding-flows/types.ts
  - portal/src/lib/onboarding-flows/flows.ts
  - portal/src/lib/onboarding-flows/index.ts
  - portal/src/lib/onboarding-flows/flows.test.ts
  - portal/src/components/onboarding/use-onboarding.ts
  - portal/src/components/onboarding/onboarding-overlay.tsx
correction_type: code
test_required: true
tests:
  - tools/audit/check-onboarding-flows.ts
  - portal/src/lib/onboarding-flows/flows.test.ts
linked_issues: []
linked_prs: []
owner: portal-ux
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Pure-domain module `portal/src/lib/onboarding-flows/` é a single
  source of truth de "qual role vê qual step do tour, em que ordem".
  Módulo não tem React, DOM ou i18n — retorna arrays ordenados de
  `OnboardingStepId` que a camada de UI traduz.

  Escopo: o portal atende **apenas staff** de assessoria
  (`admin_master`, `coach`, `assistant`) — atletas vivem no app
  mobile. Essa distinção já existe no RLS mas o tour tinha um
  único fluxo genérico de 10 steps que mostrava custody, clearing
  e distributions (módulos gated a `admin_master`) para coaches e
  assistentes.

  Política canônica (`STEP_VISIBILITY`):
    - `admin_master`: todos os 10 steps (superset)
    - `coach`: remove financial, custody, clearing, distributions
      (4 módulos que nunca vê no app por RLS)
    - `assistant`: coach ∖ {settings} (coach menos config admin)

  Invariantes asseguradas por `validateFlowInvariants()` + CI
  guard `audit:onboarding-flows` (31 asserts):
    - admin_master sempre vê todos os steps
    - coach nunca vê `custody`, `clearing`, `distributions`,
      `financial` (módulos admin-only)
    - assistant ⊆ coach (assistant é coach restrito)
    - todos os roles veem `welcome`
    - CANONICAL_ORDER é preservado por role (nunca reshuffle)
    - STEP_VISIBILITY ↔ CANONICAL_ORDER consistentes

  Wiring:
    - `useOnboarding({ role })` monta flow via
      `buildFlowForRole(role)`, usa localStorage key per-role
      (`onboarding_completed_admin_master`, `..._coach`, `..._assistant`)
      para que promoção coach→admin_master reative o tour completo.
    - `<OnboardingOverlay role={role} />` propaga a role para o hook
      e resolve `step` via `stepsById.get(flow[currentStep])`.

  Módulo tem 6 funções pure-domain (`buildFlowForRole`,
  `flowLengthForRole`, `stepIsVisibleFor`, `nextStepFor`,
  `validateFlowInvariants`) + classe `OnboardingFlowInputError`
  para roles desconhecidos, testadas por 18 unit tests vitest.

  Coin policy: L07-02 não toca `coin_ledger` — onboarding é UX
  pura, nenhum gatilho OmniCoin. Política L22-02 preservada.
---
# [L07-02] Onboarding não distingue papéis (coach, admin_master, assistant)
> **Lente:** 7 — CXO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Portal / pure-domain TS + React wiring
**Personas impactadas:** Coach, Assistant, Admin Master

## Achado
`portal/src/components/onboarding/onboarding-overlay.tsx` rodava um único fluxo linear de 10 steps para toda role do portal. Coaches viam `custody`, `clearing`, `distributions`, `financial` — módulos gated por RLS a `admin_master`. Efeito: coach sem formação financeira se sentia perdido ("custody, clearing, swap, distribute coins?!"), gerando churn D1/D7 elevado.

## Risco / Impacto
- Churn alto no D1/D7 de coaches novos.
- Assistentes vêem opções que não podem executar — UI ensina caminhos falsos.
- Promoção interna (coach → admin_master) não dispara tour novo porque completion flag era global.

## Correção aplicada

### 1. Pure-domain primitive (`portal/src/lib/onboarding-flows/`)
- `types.ts` — `CoachingRole` ("admin_master" | "coach" | "assistant"), `OnboardingStepId` (10 canonical steps), `STEP_VISIBILITY: Record<step, ReadonlySet<role>>`, `CANONICAL_ORDER`.
- `flows.ts` — `buildFlowForRole(role)`, `flowLengthForRole`, `stepIsVisibleFor`, `nextStepFor`, `validateFlowInvariants()`, `OnboardingFlowInputError`. Zero React, zero DOM.
- `index.ts` — re-exports.

### 2. Visibility policy
- `admin_master`: todos os steps (superset).
- `coach`: exclui `custody`, `clearing`, `distributions`, `financial` — apenas módulos operacionais de treino e atletas.
- `assistant`: coach ∖ {settings}.

### 3. Invariantes (CI guard + validateFlowInvariants)
- admin_master é superset obrigatório.
- coach **nunca** vê `custody` / `clearing` / `distributions` / `financial` (admin_master-only steps).
- assistant ⊆ coach.
- Todas as roles veem `welcome` primeiro.
- CANONICAL_ORDER preservado em todos os flows (subset, nunca reshuffle).

### 4. React wiring
- `useOnboarding({ role })` aceita role opcional, monta flow via `buildFlowForRole`, usa `localStorage['onboarding_completed_<role>']` para que cada role tenha seu próprio flag de completude. `totalSteps` derivado de `flow.length` (antes hard-coded a 10).
- `<OnboardingOverlay role={role} />` propaga a role, resolve step corrente via `stepsById.get(flow[currentStep])`.

### 5. Testes
- `flows.test.ts` — 18 unit tests vitest cobrindo shape do módulo, subset rules, nextStepFor walking, error path, validateFlowInvariants.
- `audit:onboarding-flows` — 31 asserts de CI guard.

## Teste de regressão
- `npm run -s test -- portal/src/lib/onboarding-flows`
- `npm run audit:onboarding-flows`

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.2]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.2).
- `2026-04-21` — Fixed via pure-domain `portal/src/lib/onboarding-flows/` + React wiring em `use-onboarding.ts` / `onboarding-overlay.tsx` + guard `audit:onboarding-flows`. Personas alinhadas com RLS: coach e assistant nunca veem financial-operator steps.
