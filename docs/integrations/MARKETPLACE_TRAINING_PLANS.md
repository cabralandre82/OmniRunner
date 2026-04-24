# Marketplace de Treinos / Planos — Spec

**Status:** Ratified (2026-04-21), implementation Wave 3+.
**Owner:** product + finance
**Related:** L16-08, L16-03 (partner API), L23-16 (coach
financial transparency), `docs/audit/findings/L09-08-*`
(multi-tenant model), L02-* (clearing), L03-* (custody).

## Question being answered

> "The `training-plan` module exists (~1500 lines of
> migration). But there's no way for a coach in Group A to
> sell their 'Marathon Plan' to athletes in Group B. The
> platform takes no marketplace fee."

## Decision

**`plan_listings` table + Stripe-powered checkout that flows
through the existing custody / platform_revenue infra.**

### Schema

```sql
CREATE TYPE public.plan_listing_status
  AS ENUM ('draft','active','paused','retired');

CREATE TABLE public.plan_listings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id         uuid NOT NULL REFERENCES training_plans(id),
  seller_group_id uuid NOT NULL REFERENCES coaching_groups(id),
  seller_user_id  uuid NOT NULL REFERENCES profiles(id),
  price_brl_cents integer NOT NULL CHECK (price_brl_cents >= 1000),
  marketplace_fee_pct numeric(5,2) NOT NULL DEFAULT 15.00
                       CHECK (marketplace_fee_pct BETWEEN 0 AND 30),
  status          plan_listing_status NOT NULL DEFAULT 'draft',
  description_md  text NOT NULL,
  cover_image_url text,
  duration_weeks  smallint NOT NULL,
  level           text NOT NULL CHECK (level IN ('beginner','intermediate','advanced')),
  goal            text NOT NULL CHECK (goal IN ('5k','10k','half','marathon','ultra','base')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  retired_at      timestamptz
);

CREATE TABLE public.plan_purchases (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id      uuid NOT NULL REFERENCES plan_listings(id),
  buyer_user_id   uuid NOT NULL REFERENCES profiles(id),
  amount_brl_cents integer NOT NULL,
  marketplace_fee_brl_cents integer NOT NULL,
  seller_payout_brl_cents integer NOT NULL,
  stripe_session_id text NOT NULL UNIQUE,
  paid_at         timestamptz,
  refunded_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.plan_listings  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_listings  FORCE  ROW LEVEL SECURITY;
ALTER TABLE public.plan_purchases FORCE  ROW LEVEL SECURITY;

CREATE POLICY listings_public_active ON public.plan_listings
  FOR SELECT USING (status = 'active');

CREATE POLICY listings_seller_full ON public.plan_listings
  FOR ALL TO authenticated
  USING (seller_user_id = auth.uid())
  WITH CHECK (seller_user_id = auth.uid());

CREATE POLICY purchases_buyer ON public.plan_purchases
  FOR SELECT TO authenticated
  USING (buyer_user_id = auth.uid());

CREATE POLICY purchases_seller ON public.plan_purchases
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM plan_listings l
                  WHERE l.id = plan_purchases.listing_id
                    AND l.seller_user_id = auth.uid()));
```

### Money flow

```
Buyer pays X BRL
     │
     ▼
Stripe collects + sends webhook
     │
     ▼
Edge Function 'plan-checkout-webhook' (idempotent on stripe_session_id)
  ├─ insert plan_purchases row, paid_at = now()
  ├─ insert platform_revenue row: source='marketplace_fee', amount = X * fee_pct
  ├─ insert coaching_groups payable: amount = X - marketplace_fee
  └─ grant access: insert into plan_assignments(buyer_user_id, plan_id)
```

The seller's payable is settled via the existing payout flow
(L23-16 PJ repassing) — same infra that pays coach
commissions. NO custody / OmniCoin layer is involved
(intentional — buying a plan is a fiat purchase, not a
coin-economy transaction).

### Refund / chargeback path

- 7-day no-questions-asked refund window enforced by
  `plan-checkout-webhook` rejecting refund requests after 7
  days unless `dispute_reason` is provided.
- A processed refund:
  - Sets `plan_purchases.refunded_at`.
  - Reverses the `platform_revenue` row (negative amount,
    `reversal_of` link).
  - Reverses the seller's payable (negative amount, settled
    against next payout).
  - Removes `plan_assignments` row → buyer loses access.
- Chargeback (Stripe `charge.dispute.created`) follows the
  L03-13 / L03-20 chargeback runbook with `domain='marketplace'`.

### UI surface

- `/marketplace/plans` (athlete-facing): browse, filter by
  goal/level/duration/price, buy.
- `/coaching/plans/[id]/listing` (seller-facing): edit listing
  metadata, price, marketplace fee % (capped 0-30%), pause /
  retire.
- `/platform/marketplace/audit`: platform_admin sees all
  listings + revenue split + dispute rate per seller.

### Anti-fraud + content moderation

- Drafts go through `/platform/marketplace/review` queue
  before going `active` — the same `social_reports`-style
  flow as L05-14 but with `category='marketplace_review'`.
- Listings flagged by ≥ 3 distinct buyers within 30 days of
  go-live are auto-paused pending review (mirrors L05-14
  auto-hide threshold).

### Why no OmniCoin payment option in v1

Tempting to let buyers pay in OmniCoins. Rejected for v1:

- Adds a "OmniCoin → BRL" conversion path on the buy side
  that doesn't exist today (only sell-side via swap).
- Tax classification gets complicated (paying for a service
  in a closed-loop token is itself a taxable event in some
  Brazilian municipalities).

We may add it in v2 once the swap marketplace has a year of
production data and the fiscal classification is settled with
the accounting firm.

## Implementation phasing

| Phase | Scope                                                            | When        |
|-------|------------------------------------------------------------------|-------------|
| 0     | Spec ratified                                                    | 2026-04-21  |
| 1     | Schema + RLS + Stripe webhook + first listings UI (sellers only) | Wave 3      |
| 2     | Marketplace browse UI + checkout                                 | Wave 3      |
| 3     | Refund + dispute paths                                           | Wave 3      |
| 4     | Review queue + auto-pause                                        | Wave 4      |
