---
id: L09-05
audit_ref: "9.5"
lens: 9
title: "IOF não recolhido em swap inter-cliente"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "compliance", "tax", "iof", "pure-domain"]
files:
  - portal/src/lib/iof/types.ts
  - portal/src/lib/iof/calculator.ts
  - portal/src/lib/iof/index.ts
  - tools/audit/check-iof-calculator.ts
correction_type: primitive
test_required: true
tests:
  - portal/src/lib/iof/calculator.test.ts
  - tools/audit/check-iof-calculator.ts
linked_issues: []
linked_prs: []
owner: platform-finance
runbook: docs/compliance/BCB_CLASSIFICATION.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Primitiva pura `portal/src/lib/iof` calcula IOF para todas as
  operações financeiras relevantes do Omni Runner:
  - `credito_pj` / `credito_pf`: daily accrual (0.0041% / 0.0082%) +
    adicional fixo 0.38%, capped em 365 dias.
  - `cambio_brl_usd_out` / `in`: 0.38% flat (Decreto 11.153/2022).
  - `seguro_vida` / `saude` / `outros`: 0.38 / 2.38 / 7.38%.
  - `titulo_privado`: 1.5%. `derivativo`: 0.005% nocional.
  - `cessao_credito_onerosa`: 0% + `collectedBy=none` — classificação
    da ADR-008 reafirmada aqui (cessão de crédito pré-existente
    entre assessorias, pagamento off-platform, **não configura
    operação de crédito nova** nos termos do CTN art. 63 I / STJ
    REsp 1.239.223), mas com warning que qualquer mudança de escopo
    (remuneração on-platform, matching ativo, intermediação)
    **exige reconsulta tributarista**.

  A primitiva retorna envelope auditável (`IofComputation`) com
  `effectiveRatePct`, `iofAmountCents`, `collectedBy`
  (`asaas | omni | none`), `legalReference` (artigo RIOF literal),
  `explanation` em PT-BR para o audit log, e `warnings` não-bloqueantes.

  Alinhado com a ADR `docs/compliance/BCB_CLASSIFICATION.md` (L09-01):
  sempre que há incidência real de IOF (câmbio ou crédito), o
  `collectedBy` é `asaas` — a IP autorizada é a contribuinte
  estatutária; Omni Runner apenas espelha o valor para reconciliação.

  Testes `calculator.test.ts` (25 cases) cobrem validação de input,
  todas as branches de `kind`, rounding bancário, cap de 365 dias,
  ausência de taxpayer em crédito, serialização JSON round-trip.

  CI guard `audit:iof-calculator` enforça 70+ invariantes (union
  de `IofOperationKind`, constantes de alíquota, ausência de IO,
  cross-ref com finding e ADR-008).
---
# [L09-05] IOF não recolhido em swap inter-cliente
> **Lente:** 9 — CRO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** Finance / Platform primitives
**Personas impactadas:** Assessoria (tesoureiro / CFO), Legal, Audit

## Achado
`execute_swap` transfere valor entre CNPJs distintos mediante taxa sem modelar IOF (Imposto sobre Operações Financeiras). Dependendo da natureza legal (crédito de marketing vs. cessão de crédito vs. ativo digital), poderia incidir IOF/Crédito de 0,38% adicional + taxa diária, ou 0,38% IOF/Câmbio.

## Risco / Impacto
- Autuação Receita Federal com juros desde a primeira operação;
- Sanção de penalidade tributária (Lei 9.430/96 art. 44);
- Distorção contábil — swap sem IOF aparente subestima custo de transferência, inflando margem falsa no ledger.

## Correção aplicada

### 1. Classificação jurídica formal (ADR-008 → esta finding)
Reafirmamos que o swap on-platform é **cessão de crédito pré-existente de custódia** (ADR-008). Per **CTN art. 63 I** combinado com STJ REsp 1.239.223 — a cessão onerosa de crédito já estabelecido **não é operação de crédito nova** para fins de IOF; o pagamento bilateral é off-platform e, portanto, fora do perímetro tributário do Omni Runner.

### 2. Primitiva pura `portal/src/lib/iof`
Módulo sem IO expõe `computeIof(input)` que retorna envelope auditável (`IofComputation`) para 10 tipos canônicos de operação:
- **Crédito PF/PJ**: 0.0082%/0.0041% diário + 0.38% adicional, cap 365 dias (Decreto 6.306/2007 art. 7 §15).
- **Câmbio BRL→USD / USD→BRL**: 0.38% flat (Decreto 11.153/2022).
- **Seguros**: 0.38/2.38/7.38% (art. 22 §1).
- **Títulos privados**: 1.5%.
- **Derivativos**: 0.005% nocional.
- **Cessão de crédito onerosa** (swap Omni Runner): 0% com `collectedBy=none` + warning de scope change.

Output inclui `effectiveRatePct`, `iofAmountCents`, `collectedBy` (asaas|omni|none), `legalReference` (artigo RIOF literal), `explanation` PT-BR, `warnings` não-bloqueantes. JSON-serializable (persist em `swap_orders.iof_quote_json` futuro, outbox events, audit logs).

### 3. Coerência com L09-01 (BCB ADR)
Onde há IOF real (câmbio, crédito), `collectedBy=asaas` — a IP autorizada BCB é a contribuinte estatutária; Omni Runner apenas **espelha** para reconciliação. Omni Runner nunca emite BRL/DARF por conta própria.

### 4. Testes + CI guard
- `calculator.test.ts` — 25 casos (validação, cada kind, rounding, cap, JSON round-trip).
- `tools/audit/check-iof-calculator.ts` — ~70 asserts (união kinds, constantes de alíquota literalmente escritas, ausência de IO, cross-refs).
- `npm run audit:iof-calculator`.

## Teste de regressão
- `npx vitest run src/lib/iof --reporter=default`
- `npm run audit:iof-calculator`

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[9.5]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 9 — CRO, item 9.5).
- `2026-04-21` — Fixed via primitiva pura `portal/src/lib/iof` + consolidação da classificação tributária na ADR-008. Swap classificado como cessão de crédito onerosa (não IOF-taxável); câmbio/crédito delegados à Asaas (L09-01).
