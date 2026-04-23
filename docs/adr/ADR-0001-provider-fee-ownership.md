# ADR-0001 — Provider fee ownership

- **Status:** Accepted
- **Date:** 2026-04-21
- **Deciders:** Finance, Platform, Founder
- **Context tag:** L09
- **Related finding(s):** `L09-08`, `L09-07`, `L03-03`

## Context

When an assessoria (coaching group) deposits funds into its
custody account, the acquiring processor (Stripe card / Asaas
PIX) charges a gateway fee. Concrete example drawn from the
finding's "2.12" narrative:

> Assessoria deposits **US$ 1,000**. Stripe bills the platform
> **US$ 38** as processing. Do we credit 962 coins (passing the
> fee through to the assessoria) or 1000 coins (platform
> absorbs)?

The ambiguity created three real risks:

1. **Consumer-law exposure (PROCON / CDC Art. 6 III).** If we
   credit 962 without a clear, pre-acceptance disclosure, the
   assessoria can claim "cobrança não contratada".
2. **Unit-economics hole.** Platform-absorb at scale means
   ~4% revenue lost to payment processing, on top of Stripe's
   published fee. At 1,000 deposits/month of median US$ 500, that
   is ~US$ 19k/month bleed.
3. **Ledger integrity.** `coin_ledger` invariants require
   that every credit has a matching `usd_receipt`. Mixing the two
   models across different deposit paths silently breaks
   reconciliation (L03-03 finding chain).

Existing plumbing:

- `platform_fee_config` already models *platform* fees
  (`signup_fee`, `delivery_fee`, `maintenance_fee`, etc.) with a
  CHECK that specifically **rejects** `provider_fee` because
  provider fees are pass-through, not configurable (see
  `20260421170000_l03_02_freeze_clearing_fee_at_emission.sql`).
- `platform_revenue` tracks `provider_fee` rows separately to
  keep fiscal reporting clean (no NFS-e on pass-through).

What is missing is the **policy switch** — does the gateway
fee go to the buyer or to the platform? Today the behaviour is
implicit in each Edge Function's math, which is precisely the
ambiguity the finding calls out.

## Options considered

1. **Platform-absorbs, always.** Simplest for the UI ("você
   recebe exatamente o valor que depositou"), hurts unit economics.
2. **Pass-through, always.** Matches how Stripe's own marketplaces
   default (Connect + Application Fee). Transparent. Requires an
   extra UI line at checkout and an opt-in during onboarding.
3. **Configurable per group.** Most flexible, but creates a
   pricing dark forest — sales conversations turn into fee
   negotiations, support burden explodes.
4. **Configurable per product (credits vs subscriptions).**
   Narrow version of #3. Still has the coordination burden and
   would need a migration for every new product.

## Decision

**Pass-through by default (Option 2)**, implemented as a single
platform-wide toggle `billing_fee_policy.gateway_passthrough`
(default `true`). The platform reserves the right to override on
a per-group basis in the future; that override is **not**
implemented today and would require a new ADR.

Rationale:

- Transparency at checkout is the cheapest way to eliminate the
  PROCON risk. The policy row drives a runtime disclosure string
  that the portal and mobile app can show verbatim.
- Unit economics survive scale without requiring a per-group
  sales dance.
- A single toggle keeps the code paths simple. The flip-the-switch
  escape hatch is cheap if we later learn that our conversion
  funnel needs "platform absorbs" to close deals with certain
  tier customers.
- Existing `platform_revenue.provider_fee` rows keep their
  semantics — the ADR does not introduce a new fee type, it only
  decides who pays the existing one.

## Consequences

**Positive**

- One row drives the math; any caller that needs to compute
  "how many coins does the buyer receive" reads the policy.
- Compliance (CDC Art. 6 III — clear disclosure) becomes a
  content problem, not an architecture problem.
- Follow-ups for per-group override (`billing_fee_policy.overrides`)
  are additive, not a rewrite.

**Negative**

- The default is slightly buyer-hostile vs "platform absorbs",
  so UX copy must compensate — the disclosure string must be
  friendly ("Stripe cobra uma taxa de X%, aplicada ao valor").
- Legacy purchases (pre-2026-04-21) carry implicit
  platform-absorb math. The migration sets the policy row to
  `gateway_passthrough=true` effective `2026-04-21`; historic
  `billing_purchases` are not retroactively reclassified (avoids
  rewriting audit history).

**Follow-ups**

- `L09-08-checkout-copy` — portal + mobile must render a
  disclosure paragraph from the policy row.
- `L09-08-contract-of-adhesion` — annex the adhesion contract
  (L04-03) with the decision so the legal basis is documented.
- `L09-08-per-group-override` — only if a sales deal demands it.
  Will need a new ADR first.
- `L09-08-historical-reclass` — one-off CSV reconciliation of
  pre-2026-04-21 purchases if an auditor asks.

## Links

- Finding: [`L09-08`](../audit/findings/L09-08-provider-fee-usd-2-12-onus-ao-cliente.md)
- Migration: `supabase/migrations/20260421440000_l09_08_billing_fee_policy.sql`
- Runbook: `docs/compliance/REFUND_POLICY.md` §1 (refund math must
  inherit the same policy).
- Related ADRs: _(none yet)_
- Related findings (ledger chain): `L03-02`, `L03-03`, `L09-07`
