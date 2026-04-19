---
id: L03-17
audit_ref: "3.17"
lens: 3
title: "Arredondamento IEEE 754 em TypeScript"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "portal"]
files:
  - portal/src/lib/money.ts
  - portal/src/app/platform/produtos/actions.tsx
correction_type: code
test_required: true
tests:
  - portal/src/lib/money.test.ts
linked_issues: []
linked_prs:
  - "c851be0"
owner: portal-team
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolved as the natural follow-up to L03-01 (which already shipped
  the BigInt + half-to-even `money.ts` helpers — `roundToCents`,
  `calcPercentFee`, `addMoney`, `subtractMoney`, `multiplyMoney`,
  `calcSplit`). The remaining `Math.round(parseFloat(s) * 100)` path
  in `portal/src/app/platform/produtos/actions.tsx` (CreateForm +
  EditForm) was the last money-impacting site silently dropping
  centavos via IEEE-754 — for inputs whose closest double lands just
  below the cent boundary (canonical: `parseFloat("1.235") * 100 ===
  123.49999…`, `Math.round → 123` instead of 124).

  **Approach.** Avoid the floating-point intermediate entirely.
  `parseDecimalToCents(input: string)` lexes the typed string into
  `(integer, fractional)` strings, normalises BR (`1.234,56`) and US
  (`1,234.56`) thousands/decimal marks, validates against
  `/^-?\d+(\.\d+)?$/`, then quantises over BigInt with banker's
  rounding (half-to-even) — bit-identical to Postgres
  `ROUND(x::numeric, 2)`. Result is exactly an integer cents value
  within `MAX_MONEY_CENTS` (or throws). UI failure mode: a malformed
  paste shows the existing "Preço inválido" toast instead of
  silently storing 0 cents.

  **Scope decision.** The audit's original file list cited
  `portal/src/lib/custody.ts:223,224,240,241`, `clearing.ts:115` and
  `swap.ts:56`, but those call-sites were already cleaned by L03-01
  via the BigInt helpers (verified by `rg "Math\.round" portal/src/lib`).
  The remaining `Math.round` usages elsewhere in the portal
  (engagement %, dashboard %, training plan progress, cron timing,
  edge-function `change_percent`, `total_km` displays) are not money
  paths — they round percentages or kilometers for display, where
  banker's vs half-up rounding has no financial impact and
  introducing the helper would be over-engineering. Those are
  intentionally left alone.

  **Tests.** 32 new vitest cases in `money.test.ts` covering
  integers, one/two/3+ fractional digits, BR comma decimal, BR/US
  thousands separators, explicit + sign, negatives, leading zeros,
  banker's rounding (1.005 → 100, 1.015 → 102, 1.025 → 102,
  sign-symmetric -1.005 → -100), digits-beyond-3 tail, malformed-
  input rejection (empty, abc, 1.2.3, 1e5, ".5", "1.", NaN,
  Infinity, currency symbols, sign-only), range enforcement
  (MAX_MONEY_CENTS ± 1), parity against an independent BigInt
  reference oracle on 1,000 fuzzed inputs, and round-trip via the
  `(cents/100).toFixed(2)` display path. A sweep test asserts that
  at least one half-cent input *actually diverges* from
  `Math.round(parseFloat(s) * 100)` on the test runtime — proves
  the migration is not a no-op on this engine.

  Portal suite: 1180/0 (was 1138 pre-L03-17, +42 from money.test.ts
  additions). Audit verify: 348/348.
---
# [L03-17] Arredondamento IEEE 754 em TypeScript
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed (2026-04-17)
**Camada:** PORTAL
**Personas impactadas:** Atletas (compradores de OmniCoins), platform admins (cadastro de produtos).
## Achado
Pre-fix, o admin form `platform/produtos/actions.tsx` convertia preços tipados em centavos via:

```typescript
const price_cents = Math.round(parseFloat(priceStr) * 100);
```

Para valores cuja representação IEEE-754 mais próxima cai logo abaixo da fronteira do centavo:

  - `parseFloat("1.235")` → 1.235 (canonical), mas `1.235 * 100 = 123.49999999999999` em algumas combinações de input → `Math.round → 123` (esperado 124).
  - `parseFloat("0.295") * 100` → similar comportamento dependente do engine.

Resultado: centavo silenciosamente perdido no `price_cents` armazenado, propagando para o display de "preço por OmniCoin" no shop e gerando ticket recorrente de atletas reportando "preço estranho".

L03-01 (já fechado) introduziu `portal/src/lib/money.ts` com helpers BigInt + banker's rounding (`roundToCents`, `calcPercentFee`, etc.) e migrou os call-sites de fee math em `custody.ts`/`clearing.ts`/`swap.ts`. Este finding fecha o último call-site money-impacting que ainda dependia de `Math.round(parseFloat * 100)`.

## Correção aplicada

Novo helper string-only `parseDecimalToCents(input)` em `money.ts` (149 linhas com docstring + impl):

  1. Trim + sanitização de sinal (`+`/`-`).
  2. Resolução de separador decimal vs milhar (suporta `1.234,56` BR, `1,234.56` US, e formas com apenas um separador).
  3. Validação contra `/^-?\d+(\.\d+)?$/` — exponentiação (`1e5`), múltiplos pontos, símbolos (`R$`) rejeitados.
  4. Decode em BigInt (`mantissa`, `scale`) — zero floating-point.
  5. Quantização para 2 casas via `roundDecimal` existente (banker's, mesma função usada por `roundToCents` / `calcPercentFee`).
  6. `assertWithinRange` valida contra `MAX_MONEY_CENTS`.
  7. Retorna integer cents como `number` (`Number(BigInt)` é lossless dentro de safe-int).

`actions.tsx` migrado em `EditForm` e `CreateForm`: try/catch redireciona malformed input ao toast existente "Preço inválido" ao invés de silenciosamente zerar o `price_cents`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.17).
- `2026-04-17` — Fix completo (commit `c851be0`): `parseDecimalToCents` + migração dos 2 call-sites + 32 testes incluindo oracle BigInt + 1k fuzz.