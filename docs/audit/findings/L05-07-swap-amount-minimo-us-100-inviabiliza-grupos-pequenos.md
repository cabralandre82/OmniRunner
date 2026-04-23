---
id: L05-07
audit_ref: "5.7"
lens: 5
title: "Swap: amount mínimo US$ 100 inviabiliza grupos pequenos"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "portal", "ux", "marketplace"]
files:
  - portal/src/lib/swap.ts
  - portal/src/app/api/swap/route.ts
  - portal/src/lib/openapi/routes/v1-financial.ts
  - portal/public/openapi.json
  - portal/src/app/(portal)/swap/swap-actions.tsx
correction_type: code
test_required: true
tests:
  - portal/src/lib/swap.test.ts
  - portal/src/app/api/swap/route.test.ts
  - portal/src/app/(portal)/swap/swap-actions.test.tsx
linked_issues: []
linked_prs:
  - 1ad1a91ad459ba52b5edbb7764d017041e5886b3
owner: cpo+frontend
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-07] Swap: amount mínimo US$ 100 inviabiliza grupos pequenos

> **Lente:** 5 — CPO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** marketplace P2P · **Personas impactadas:** admin_master de clube amador, atletas amadores

## Achado original
`portal/src/app/api/swap/route.ts:40` declarava
`amount_usd: z.number().min(100).max(500_000)` no Zod schema da ação
`create`. Um clube de 20 atletas que quisesse hedge de US$ 50 era
**bloqueado no front-end** (UI também tinha `min={100}` em
`swap-actions.tsx:106` e validação `val < 100` em `handleCreate`)
e **bloqueado no backend** (Zod retornava 400 VALIDATION_FAILED).
Resultado: os segmentos amadores nunca conseguiam usar o marketplace
P2P de lastro — feature inviável fora de clubes profissionais com
volumes ≥ US$ 1.000/swap.

O floor de US$ 100 foi fixado em PR antigo sem rationale documentado;
provavelmente herdado de um early-stage onde fee fixo do gateway
fazia US$ 50 swaps inviáveis. Pós-L03-01 (money math TS↔SQL) +
L05-02 (TTL) + L02-07 (off-platform payment ref) o swap é
puramente intra-plataforma — não tem custo marginal por amount,
só fee proporcional (`platform_fee_config.swap.rate_pct` = 1%
default).

## Risco / Impacto pré-fix
- **Adoção limitada nos segmentos amadores**: clubes com 20-50
  atletas fazem swaps de US$ 30-200 typicamente; floor US$ 100
  filtrava ~60% do mercado-alvo amador.
- **Atletas amadores nunca veem valor no P2P**: marketplace
  inflow/outflow vazio em produto inicial → loop de
  feedback negativo (sem oferta → sem demanda → sem oferta).
- **Distorção competitiva pró-clubes-grandes**: única forma de
  liquidez P2P era entre clubes com US$ 100+ disponíveis,
  reforçando dinâmica winner-takes-all.

## Correção entregue (commit `1ad1a91`, 2026-04-21)

### 1. Constantes canônicas em `portal/src/lib/swap.ts`
Exporta `SWAP_MIN_AMOUNT_USD = 10` e `SWAP_MAX_AMOUNT_USD = 500_000`
como single source of truth, com comment explicativo:

- **Floor 10**: pega o segmento amador (clubes 20-50 atletas com
  swaps de US$ 30-200) sem permitir dust transactions
  (sub-US$ 1 que polui CFO reconciliation e platform_fee
  ledger). Fee mínimo a 1% = US$ 0.10 que ainda é >= dust
  precisão de `numeric(14,2)`.
- **Cap 500_000**: tamanho típico de uma rodada institucional;
  acima disso o tesoureiro divide em múltiplas ofertas
  (defesa contra digit-fat-finger UI desktop).

### 2. Wiring em 3 superfícies (lockstep)
- **`portal/src/app/api/swap/route.ts`** importa as constantes
  e usa em `createSchema.amount_usd.min/max(...)`.
- **`portal/src/lib/openapi/routes/v1-financial.ts`** importa as
  constantes e usa em `SwapCreateBody.amount_usd.min/max(...)`,
  além de incluir o L05-07 ref na descrição OpenAPI.
- **`portal/public/openapi.json`** (legacy hand-maintained spec)
  atualizado de `minimum: 100` → `minimum: 10` com descrição
  citando L05-07.
- **`portal/src/app/(portal)/swap/swap-actions.tsx`** (UI client
  component) importa `SWAP_MIN_AMOUNT_USD`, usa em `<input min={...}>`,
  no guard `handleCreate` (`val < SWAP_MIN_AMOUNT_USD`) e na
  message (`Valor mínimo: US$ ${SWAP_MIN_AMOUNT_USD.toFixed(2)}`).
  Adiciona helper text `<p>` com `aria-describedby` mostrando
  range explicitamente: "Mínimo US$ 10.00 · máximo US$ 500.000,00".

### 3. Schema do banco INALTERADO
`swap_orders.amount_usd numeric(14,2) NOT NULL CHECK (amount_usd > 0)`
em `20260228150001_custody_clearing_model.sql:172` continua intacto.
O CHECK de >0 é defesa econômica (não permitir receita negativa);
o floor de UX (US$ 10) é decisão de produto que pode evoluir sem
migration. Documentação em `swap.ts` cita ambos para contributor
clarity.

### 4. Tests adicionados/atualizados
- **`portal/src/lib/swap.test.ts`** (+3 cases em novo describe
  `"L05-07 — SWAP_MIN_AMOUNT_USD lockstep contract"`):
  (i) constantes com valores esperados (10, 500_000),
  (ii) lockstep contract test que **lê literalmente
  `portal/public/openapi.json`** e asserta que
  `paths."/api/swap".post.requestBody...amount_usd.minimum === 10`
  — falha CI em O(1) se hand-maintained spec e Zod desviarem,
  (iii) lockstep contract test que **lê o source de
  `swap-actions.tsx`** e asserta que importa `SWAP_MIN_AMOUNT_USD`
  de `@/lib/swap` (não literais hardcoded), garantindo que
  refatorações futuras do floor refletem em UI sem busca manual.
- **`portal/src/app/api/swap/route.test.ts`** (test "amount below
  minimum" updated de 10 → 5; +2 novos casos):
  (i) US$ 10 (floor exato) é aceito pelo route + RPC chamado
  com `amount=10`,
  (ii) regressão US$ 50 (rejected pre-fix) é aceito.
- **`portal/src/app/(portal)/swap/swap-actions.test.tsx`** (test
  message updated; +3 novos casos):
  (i) helper text aparece com texto canônico,
  (ii) US$ 5 ainda rejeitado com message com novo valor,
  (iii) US$ 10 (floor exato) aceito sem message,
  (iv) regressão US$ 50 aceito sem message.

Suite local **95/95** verde (swap.test + route.test + swap-actions.test
+ v1-aliases). `npm run openapi:check` OK (drift 0, coverage 55+39
grandfathered).

### 5. Backwards compat
- 100% — existing clientes que enviavam `amount_usd ≥ 100` continuam
  funcionando idêntico.
- Existing swap_orders no banco (criadas com floor antigo) ficam
  intactas (status enum e CHECK não mudaram).
- Apenas o conjunto-de-aceitação cresceu para `amount_usd ∈ [10, 500_000]`.

### 6. Considerações de produto/UX explicitadas
- **Por que não 1?** Dust attacks. Floor de US$ 1 permitiria
  spammer criar 1.000 ofertas de US$ 1 saturando o painel "open
  swaps" do clube. US$ 10 + rate-limit 10/min ainda permite
  ataques teóricos mas com custo material visível ao CFO.
- **Por que não 5?** US$ 0.05 fee (1% de 5) é abaixo da precisão
  econômica útil + cria ruído em `platform_revenue` ledger.
  US$ 10 com US$ 0.10 fee é o break-even.
- **Quando subir cap 500k?** Mantém. Cap baseia-se em "tesoureiro
  digitando manualmente"; rodadas institucionais maiores devem
  usar API direta (`/api/v1/swap`) com sanity-check no integrador
  ou dividir em N ofertas (preserva auditoria granular).

## Referência narrativa
Contexto completo e motivação detalhada em
[`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.7]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO,
  item 5.7).
- `2026-04-21` — **Fix shipped**: floor US$ 100 → US$ 10 via
  constantes canônicas em `portal/src/lib/swap.ts` reusadas em
  route handler, OpenAPI v1, OpenAPI legacy e UI; lockstep
  contract tests garantem zero drift entre as 4 superfícies.
  Audit verify 348/348.
