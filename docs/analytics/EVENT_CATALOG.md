# Product event catalog (L08-09)

> **Status:** canonical · **Owner:** Data + Product · **Last
> updated:** 2026-04-21

This catalog is the single source of truth for the
`public.product_events` table. The trigger
`fn_validate_product_event` (in
`supabase/migrations/20260421100000_l08_product_events_hardening.sql`),
the TypeScript schema in
[`portal/src/lib/product-event-schema.ts`](../../portal/src/lib/product-event-schema.ts),
and the Dart tracker in
[`omni_runner/lib/core/analytics/product_event_tracker.dart`](../../omni_runner/lib/core/analytics/product_event_tracker.dart)
each carry a copy of these names + property keys. Drift between
the three is a CI failure (`tools/test_l08_01_02_product_events_hardening.ts`).

## Contract

* `event_name` — picked from a closed enum (see § Events). New
  names cannot be added without a migration; that is intentional.
* `properties` — flat JSON object. Keys MUST come from the
  whitelist (see § Property keys). Values MUST be `string`,
  `number`, `boolean`, or `null`. Strings are capped at
  **200 chars**. Nested objects/arrays are rejected with
  SQLSTATE `PE003`.
* `user_id` — required, taken from the authenticated session;
  never sent from the client untrusted body.
* PII fields are **forbidden** (see § PII guardrails).

## Events

| Event name                   | One-shot? | Trigger                                                                                              | Required property keys           |
|------------------------------|-----------|------------------------------------------------------------------------------------------------------|----------------------------------|
| `billing_checkout_returned`  | no        | User returns from external checkout (Stripe Hosted) to portal/mobile.                                | `outcome` (`paid`/`abandoned`)   |
| `billing_credits_viewed`     | no        | User opens the credits / wallet screen.                                                              | —                                |
| `billing_purchases_viewed`   | no        | User opens the purchases history screen.                                                             | —                                |
| `billing_settings_viewed`    | no        | User opens the billing settings screen.                                                              | —                                |
| `first_challenge_created`    | yes       | The first time a coach creates a challenge for their group.                                          | `challenge_id`                   |
| `first_championship_launched`| yes       | The first time a coach publishes a championship.                                                     | `championship_id`                |
| `flow_abandoned`             | no        | A multi-step flow (onboarding, checkout, challenge wizard) is exited before the terminal step.       | `flow`, `step`                   |
| `onboarding_completed`       | yes       | User finishes the onboarding wizard (mobile + portal share this single milestone).                   | `role`                           |

"One-shot" events are protected by the partial unique index
`idx_product_events_user_event_once` on `(user_id, event_name)`.
The Dart tracker swallows `unique_violation` (SQLSTATE `23505`)
on these events as the idempotent path under double-tap or
offline resync.

## Property keys

| Key              | Type             | Purpose                                                       |
|------------------|------------------|---------------------------------------------------------------|
| `balance`        | number           | Account balance at the time of the event (no currency code).  |
| `challenge_id`   | UUID-as-string   | The challenge under inspection.                               |
| `championship_id`| UUID-as-string   | The championship under inspection.                            |
| `count`          | number           | A counter relevant to the event (e.g. items shown).           |
| `duration_ms`    | number           | How long the flow / view took (use only when actionable).     |
| `flow`           | enum-string      | Logical flow name. See § Flow names.                          |
| `goal`           | enum-string      | Athlete training goal — `weight_loss` / `5k` / `10k` / etc.   |
| `group_id`       | UUID-as-string   | The coaching group context.                                   |
| `method`         | enum-string      | Auth method, payment method, etc. — never the secret itself.  |
| `metric`         | enum-string      | A KPI label (e.g. `weekly_volume_km`).                        |
| `outcome`        | enum-string      | Terminal outcome. See § Outcome values.                       |
| `products_count` | number           | Cart size. Used by `billing_*` events.                        |
| `reason`         | enum-string      | Reason code for negative outcomes (`network_error`, etc.).    |
| `role`           | enum-string      | `athlete` / `coach` / `admin_master` / `staff`.               |
| `step`           | enum-string      | Step name inside a `flow_abandoned` event.                    |
| `template_id`    | UUID-as-string   | Championship template used in setup.                          |
| `total_count`    | number           | Sibling to `count` for "out of N" framings.                   |
| `type`           | enum-string      | A polymorphic type tag. Use only when no narrower key fits.   |

## Flow names

`flow` is set to one of:

* `onboarding`
* `coach_setup`
* `challenge_create`
* `championship_setup`
* `checkout`
* `staff_invite`
* `wallet_topup`

If a new flow needs tracking, extend this list and the trigger
constant `v_allowed_keys` in the same migration commit.

## Outcome values

`outcome` is set to one of:

* `paid`           — checkout completed.
* `abandoned`      — user closed the flow.
* `network_error`  — recoverable backend / network error.
* `validation_error` — client-side validation rejected input.
* `not_eligible`   — user is not allowed to perform the action
  (e.g. coach trying to start an athlete-only flow).

## PII guardrails

The trigger rejects any property key not on the whitelist with
SQLSTATE `PE002`. The whitelist explicitly excludes:

* `email`, `cpf`, `phone`, `address`, `ip_address`, `device_id`,
* `name`, `nickname`, `avatar_url`,
* `lat`, `lng`, `polyline`, `geohash`,
* `comment`, `note`, `feedback` (free-text vectors).

If a product question genuinely needs one of those, escalate to
the DPO and ship through the `audit_logs` table (which has a
narrower retention window and stronger access controls), not
through `product_events`.

## How to add an event

The runbook lives at
[`docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md`](../runbooks/PRODUCT_EVENTS_RUNBOOK.md)
("4 places to update") and is the canonical PR checklist.

## How to add a property key

1. Add the key to the table in this catalog with a clear purpose
   and one-line value description.
2. Add the key to `PRODUCT_EVENT_PROPERTY_KEYS` in
   `portal/src/lib/product-event-schema.ts`.
3. Add the key to `ProductEvents.allowedPropertyKeys` in
   `omni_runner/lib/core/analytics/product_event_tracker.dart`.
4. Add the key to `v_allowed_keys` in a new migration (do **not**
   edit the original migration — it has already shipped).
5. Confirm the integration test
   `tools/test_l08_01_02_product_events_hardening.ts` still
   passes (it asserts cross-language whitelist parity).

## See also

* [`docs/runbooks/PRODUCT_EVENTS_RUNBOOK.md`](../runbooks/PRODUCT_EVENTS_RUNBOOK.md)
  — PR checklist + on-call playbook for trigger PE001..PE005
  errors.
* [`portal/src/lib/product-event-schema.ts`](../../portal/src/lib/product-event-schema.ts)
  — TypeScript canonical constants + `validateProductEvent()`.
* [`omni_runner/lib/core/analytics/product_event_tracker.dart`](../../omni_runner/lib/core/analytics/product_event_tracker.dart)
  — Dart canonical constants + `ProductEvents.validate()`.
* `supabase/migrations/20260421100000_l08_product_events_hardening.sql`
  — the trigger `fn_validate_product_event` and partial index
  `idx_product_events_user_event_once`.
