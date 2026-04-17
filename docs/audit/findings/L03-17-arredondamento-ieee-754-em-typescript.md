---
id: L03-17
audit_ref: "3.17"
lens: 3
title: "Arredondamento IEEE 754 em TypeScript"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal"]
files:
  - portal/src/lib/custody.ts
correction_type: process
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
# [L03-17] Arredondamento IEEE 754 em TypeScript
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** —
## Achado
`portal/src/lib/custody.ts:223,224,240,241,115 (clearing.ts),56 (swap.ts)`: uso generalizado de `Math.round(x * 100) / 100`. Para valores onde `x * 100` não é representável exatamente (IEEE 754), há erro silencioso:
  - `0.1 + 0.2 = 0.30000000000000004` — `Math.round(0.30000000000000004 * 100) / 100 = 0.3` ✓
  - `1.005 * 100 = 100.49999999999999` (**não 100.5**) → `Math.round(100.4999...) = 100` → `1.00` (**esperado 1.01 bancário**)
## Risco / Impacto

Centavos faltantes em operações de saldo formatadas para display. Divergência UI vs DB.

## Correção proposta

Usar library `decimal.js` ou `big.js` para toda matemática financeira no TS. Exemplo:
```typescript
import Decimal from "decimal.js";
Decimal.set({ rounding: Decimal.ROUND_HALF_EVEN }); // banker's
export function roundCents(v: number | string): number {
  return new Decimal(v).toDecimalPlaces(2, Decimal.ROUND_HALF_EVEN).toNumber();
}
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.17]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.17).