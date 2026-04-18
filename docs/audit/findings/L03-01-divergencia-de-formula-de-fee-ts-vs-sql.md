---
id: L03-01
audit_ref: "3.1"
lens: 3
title: "Divergência de fórmula de fee — TS vs SQL"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["finance", "money", "rounding", "portal", "billing"]
files:
  - portal/src/lib/money.ts
  - portal/src/lib/clearing.ts
  - portal/src/lib/swap.ts
  - portal/src/lib/custody.ts
  - portal/src/lib/billing/edge-cases.ts
  - portal/src/lib/qa-reconciliation.test.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/money.test.ts
linked_issues: []
linked_prs:
  - "commit:3958b00"
owner: backend-platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Onda 1, 2026-04-17. Divergência eliminada via novo módulo
  `portal/src/lib/money.ts` que implementa banker's rounding
  (half-to-even) sobre BigInt mantissa, replicando bit-a-bit
  `Postgres ROUND((g * r / 100)::numeric, 2)`.

  Substitui `Math.round(g * r) / 100` em 5 call-sites do portal:
  clearing.ts, swap.ts, custody.ts, billing/edge-cases.ts e o teste
  de reconciliação. Funções SQL (`execute_burn_atomic`,
  `execute_swap`, `execute_withdrawal`) já usam a fórmula correta
  desde `20260303100000_gateway_fee_backing_fix.sql` e
  `20260417140000_execute_burn_atomic_hardening.sql` — esta correção
  alinha o lado TS.

  Property-based test executa 5.000 pares aleatórios (gross,
  ratePct) e verifica equivalência contra implementação BigInt de
  referência do `ROUND` do Postgres. Cobre exact-half boundaries
  (0.005 → 0.00, 0.015 → 0.02) onde `Math.round` diverge.

  `processBurnForClearing` permanece no repo mas marcado
  `@deprecated`: produção usa `executeBurnAtomic`, mas testes
  legados (`qa-e2e`, `concurrency`, `clearing.test`) ainda exercitam
  o caminho não-atômico. Manter o código + corrigir a aritmética
  evita drift caso algum caller legado seja descoberto antes da
  remoção definitiva.
---
# [L03-01] Divergência de fórmula de fee — TS vs SQL
> **Lente:** 3 — CFO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** 🟢 fixed
**Camada:** PORTAL + BACKEND
**Personas impactadas:** Plataforma (receita), Assessoria (pagamentos)
## Achado
`portal/src/lib/clearing.ts:115`: `const feeUsd = Math.round(grossUsd * feeRate) / 100;` ← fórmula **legada**.
  - `supabase/migrations/20260303100000_gateway_fee_backing_fix.sql:45-46` mudou `execute_burn_atomic` para `ROUND(v_gross * v_fee_rate / 100, 2)`.
  - `processBurnForClearing` (clearing.ts:57-173) **não é mais chamado** se o fluxo correto usa `executeBurnAtomic` (linha 186-202). Mas o código TS persiste no repo e pode ser chamado por legacy callers.
  - Para `grossUsd = 33.33, feeRate = 3.0`:
    - TS (`Math.round(33.33 * 3.0) / 100`) = `Math.round(99.99) / 100` = `100 / 100` = `1.00`
    - SQL novo (`ROUND(33.33 * 3.0 / 100, 2)`) = `ROUND(0.9999, 2)` = `1.00`
## Risco / Impacto

Divergência entre receita esperada (cálculo TS no portal/UI) e receita real (cálculo SQL durante burn). Centavos por burn × milhares de burns/mês = desvio significativo em relatórios. CFO reporta números diferentes do DB.

## Correção proposta

1. Remover `Math.round(x * y) / 100` e substituir por helper que replica a semântica de `numeric(14,2)`:
  ```typescript
  // portal/src/lib/money.ts
  export function roundCents(value: number): number {
    // Replica Postgres ROUND(value, 2) com banker's rounding
    const x = value * 100;
    const rounded = Math.abs(x % 1) === 0.5
      ? (Math.floor(x) % 2 === 0 ? Math.floor(x) : Math.ceil(x))
      : Math.round(x);
    return rounded / 100;
  }
  export function calcFee(gross: number, ratePct: number): number {
    return roundCents(gross * ratePct / 100);
  }
  ```
  2. Melhor: mover **todo** cálculo financeiro para SQL. TS só exibe valor já calculado.
  3. Adicionar teste property-based que compara cálculo TS vs SQL para 10k valores aleatórios.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.1]`.

## Correção implementada (2026-04-17, commit `3958b00`)

### Novos arquivos

| Arquivo | Linhas | Descrição |
|---|---|---|
| `portal/src/lib/money.ts` | ~360 | Helper canônico (`roundToCents`, `calcPercentFee`, `addMoney`, `subtractMoney`, `multiplyMoney`, `calcSplit`) com BigInt + banker's rounding |
| `portal/src/lib/money.test.ts` | ~340 | 22 testes incluindo property-based (5.000 pares) contra implementação BigInt de referência do `ROUND` do Postgres |

### Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `portal/src/lib/clearing.ts` | `processBurnForClearing` agora usa `calcPercentFee` + `subtractMoney`; adicionado `@deprecated` |
| `portal/src/lib/swap.ts` | `createSwapOffer` usa `calcPercentFee` |
| `portal/src/lib/custody.ts` | `convertToUsdWithSpread` / `convertFromUsdWithSpread` usam `roundToCents` |
| `portal/src/lib/billing/edge-cases.ts` | `calculateSplitValue` delega a `calcSplit` (split sempre fecha exatamente) |
| `portal/src/lib/qa-reconciliation.test.ts` | Reconciliação 6.3 usa `calcPercentFee` |

### Mecânica da equivalência com Postgres

`calcPercentFee(gross, ratePct)` decompõe cada input via
`Number.toString()` (string decimal mais curta que round-trippa para o
mesmo `number`), constrói mantissas BigInt + escala, multiplica,
adiciona 2 à escala (o `/100` da fórmula percentual), e arredonda à
escala 2 com half-to-even. Resultado bit-a-bit idêntico a:

```sql
ROUND((gross::numeric * rate_pct::numeric / 100)::numeric, 2)
```

— exatamente a fórmula consagrada em `gateway_fee_backing_fix.sql` e
`execute_burn_atomic_hardening.sql`.

### Por que isto era crítico

Para um fluxo `gross=2.5, rate=1.0%`:

- **Antes (TS):** `Math.round(2.5 * 1.0) / 100 = 0.03` (round-half-away)
- **SQL (Postgres):** `ROUND(0.025, 2) = 0.02` (banker's: 2 é par)

Discrepância de 1 cent em ~1 a cada 5 burns que caem em boundary
exato. A 5k clearings/dia em GA = ~1.000 cents/dia de drift, sem
contar o impacto na confiança do número exibido na UI vs cobrado no DB.

### Testes (22/22 passando)

1. `roundToCents` trivial values
2. `roundToCents` absorve IEEE-754 drift (`0.1+0.2 → 0.3`)
3. `roundToCents` banker's nas fronteiras .005, .015, .345, .355
4. `roundToCents` simétrico para negativos
5. `roundToCents` rejeita NaN/Infinity
6. `roundToCents` rejeita valores fora de `numeric(14,2)`
7. `roundToCents` matches Postgres ROUND para 5.000 valores aleatórios
8. `roundToCents` half-to-even em todas as 100 posições de cents
9. `calcPercentFee` valores documentados (60×3% = 1.80 etc)
10. `calcPercentFee` banker's vs `Math.round` (4 contraprovas)
11. `calcPercentFee` matches Postgres para 5.000 (gross, rate) aleatórios
12. `calcPercentFee` happy-path preserva valores antigos
13. `calcPercentFee` rejeita não-finitos
14. `subtractMoney` absorve drift (`100 - 3 = 97.00` exato)
15. `subtractMoney` comuta com `calcPercentFee` (gross = fee + net)
16. `addMoney` absorve drift
17. `multiplyMoney` arredonda produto para cents
18-22. `calcSplit` (4 cenários + 1.000 splits aleatórios sem drift)

### Validação completa

- ✅ `npx tsc --noEmit` — clean
- ✅ `npx next lint` — 0 warnings
- ✅ `npx vitest run` — 864 passing, 4 todo, 0 falhas
- ✅ `npx tsx tools/audit/verify.ts` — 348 findings validados

### O que não foi feito (escopo intencional)

- Não removemos `processBurnForClearing`. Apenas marcado
  `@deprecated` — a remoção depende de migrar `qa-e2e.test.ts`,
  `concurrency.test.ts` e `clearing.test.ts` para mockar
  `executeBurnAtomic` em vez de exercitar o caminho legado.
- Não introduzimos lint rule contra `Math.round(x) / 100`. O custo
  de falsos-positivos (não-money rounds) supera o benefício dado
  que os 6 call-sites de money foram inventariados.
- L03-17 (IEEE 754 generalizado) permanece em aberto para os pontos
  fora de fee/spread (e.g. `convertToUsdWithSpread` no caminho FX
  ainda multiplica antes de quantizar; corrigido aqui via
  `roundToCents` mas não cobre o domínio inteiro do L03-17).

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.1).
- `2026-04-17` — Correção implementada (`portal/src/lib/money.ts` + 5 call-sites + 22 testes). Promovido a `fixed` (commit `3958b00`).