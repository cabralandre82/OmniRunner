# FX Spread Disclosure (L03-06)

**Audit reference:** L03-06 — _FX spread cálculo simétrico entrada/saída_.
**Owner:** Finance · **Last reviewed:** 2026-04-21.

## What is the FX spread?

The Omni Coin custody flow converts between the user's local currency
and USD whenever:

  * The user **deposits** local currency to acquire OmniCoins
    (on-ramp), and
  * The user **withdraws** USD-denominated balances back to local
    currency (off-ramp).

Each leg applies a configurable spread on top of the mid-market rate.
The default is **0.75 %** per leg, sourced from
`public.platform_fee_config WHERE fee_type='fx_spread'`.

## The round-trip cost is symmetric

Because the spread is charged on **both** the entry and the exit leg,
a user who deposits and immediately withdraws the same amount loses
**~1.50 %** to the spread, not 0.75 %. The two legs compose
multiplicatively:

```
net_after_round_trip = amount × (1 - spread) × (1 - spread)
                     ≈ amount × (1 - 2·spread)   for spread « 1
```

Concrete example (spread = 0.75 %, amount = USD 1 000.00):

| step       | amount (USD) | running cost |
| ---------- | -----------: | -----------: |
| deposit    |     1 000.00 |        0.00  |
| credited   |       992.50 |        7.50  |
| withdraw   |       992.50 |        7.50  |
| received   |       985.06 |       14.94  |

## Where this is implemented

  * `portal/src/lib/custody.ts:convertToUsdWithSpread`   — entry leg
  * `portal/src/lib/custody.ts:convertFromUsdWithSpread` — exit leg
  * `public.platform_fee_config` — single source of truth for `rate_pct`

Both helpers use banker's rounding to cents (L03-01) so each leg
matches the Postgres `numeric(14,2)` representation byte-for-byte.

## Disclosure obligations

* The deposit confirmation screen MUST display the spread in USD
  alongside the gross amount (component
  `portal/src/app/credits/components/DepositConfirm.tsx`).
* The withdrawal confirmation screen MUST surface the round-trip
  effective cost ("Você está sacando X. Considerando o spread de
  entrada já pago + 0,75% agora, o custo total foi Y") so the user
  is never surprised — this is the L03-06 mitigation.
* The credits help center page (`/help/credits`) links to this
  document.

## Future considerations (NOT implemented)

  * **Entry-only spread:** charge 1.50 % on the on-ramp and 0 % on
    off-ramp. Better optics; identical revenue. Requires migration
    to `platform_fee_config.fee_type='fx_spread_entry'` and a UI
    revamp. Tracked as a candidate for the next product cycle.

## Cross-refs

  * L03-06 (this finding)
  * L03-01 — banker's rounding to cents
  * L03-02 — clearing fee freeze at emission
  * L09-11 — clearing is multilateral compensation, not credit assignment
