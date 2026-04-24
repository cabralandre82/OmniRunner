# Public API — Idempotency-Key Contract

**Status:** Active (2026-04-21)
**Owner:** platform + finance
**Related:** L14-07, L18-02 (server-side wrapper),
`docs/runbooks/IDEMPOTENCY_RUNBOOK.md`.

## TL;DR

Every state-mutating financial endpoint MUST accept an
**Idempotency-Key** from the client. Replays within 24 h return
the original `(status, body)` byte-for-byte. Missing key → `400
MISSING_IDEMPOTENCY_KEY`. Same key + different body → `409
IDEMPOTENCY_KEY_CONFLICT`.

## Header / body contract

The key may be supplied either as:

- HTTP header `Idempotency-Key: <opaque>` (RFC-aligned name),
  also accepted as the lower-case `x-idempotency-key` for
  backward compatibility with older mobile clients.
- A field `idempotency_key: <opaque>` in the JSON request body.

Both are accepted; if both are present and differ, the body
field wins (it is harder to MITM-substitute). Length: 8–128
characters, opaque ASCII (UUID v4 strongly recommended).

## Endpoints in scope (today)

| Endpoint                                                        | Namespace                  | Notes |
|-----------------------------------------------------------------|----------------------------|-------|
| `POST /api/distribute-coins`                                    | `coins.distribute`         | Single-recipient mint |
| `POST /api/distribute-coins/batch`                              | `coins.distribute_batch`   | Up to 200 recipients/tx |
| `POST /api/coins/reverse`                                       | `coins.reverse`            | Refund / chargeback reversal |
| `POST /api/custody`                                             | `custody.deposit`          | Deposit creation |
| `POST /api/custody/withdraw`                                    | `custody.withdraw`         | Withdrawal request |
| `POST /api/checkout`                                            | `billing.checkout`         | Stripe checkout proxy |
| `POST /api/auto-topup`                                          | `billing.auto_topup`       | Toggle auto-topup |
| `POST /api/v1/custody`                                          | `custody.deposit_v1`       | Public-API custody deposit |
| `POST /api/platform/custody/withdrawals/[id]/complete`          | `custody.withdraw_complete`| Operator close-out |
| `POST /api/platform/custody/withdrawals/[id]/fail`              | `custody.withdraw_fail`    | Operator failure path |
| `POST /api/platform/custody/[groupId]/daily-cap`                | `custody.daily_cap`        | Cap config update |

Endpoints **out of scope** by design:

- `POST /api/swap` (create/accept/cancel) — relies on
  per-action server-side state machines and `FOR UPDATE`
  ordering (L05-01, L01-05). Idempotency would be a layer on
  top of the existing P0001/P0002/P0003 SQLSTATE map.
- Any `GET` / `HEAD` — naturally idempotent.
- Webhook receivers (Stripe, MercadoPago, Asaas) — providers
  carry their own idempotency keys (`Stripe-Signature`,
  `idempotency_key` from MercadoPago webhook envelope); we
  honour the provider's key, not a client-supplied one
  (L01-01, L01-18).

## Server-side replay storage

`public.idempotency_keys` (see L18-02 migration). Per-row
contract:

```
PRIMARY KEY (namespace, actor_id, key)
- request_hash : sha256(canonical_json(body))
- response     : (status, body) cached for 24 h
- TTL          : 24 h after first write; GC by hourly cron.
```

The wrapper `withIdempotency()` in
`portal/src/lib/api/idempotency.ts` is the only call-site that
reads/writes the table. Routes opt in by wrapping their
handler:

```ts
export const POST = withErrorHandler(
  withIdempotency("custody.withdraw", _post),
  "api.custody.withdraw.post",
);
```

If the wrapper sees `mode = 'execute'` it runs the handler then
calls `fn_idem_finalize`. If `mode = 'replay'` it returns the
cached response. If `mode = 'mismatch'` (same key, different
body hash) it returns `409 IDEMPOTENCY_KEY_CONFLICT`.

## Failure semantics

- **Missing key on a route in scope** → `400
  MISSING_IDEMPOTENCY_KEY`. Mobile / portal MUST mint a UUID
  v4 client-side and persist it across retries of the same
  user-intent (e.g. "the user pressed Withdraw and we are now
  retrying because the network dropped before the response").
- **5xx during handler execution** → row is left in `executing`
  state with a 60 s lock; client retry within the lock window
  gets `409 IDEMPOTENCY_KEY_INFLIGHT` (so they can back off
  with jitter). After the lock expires the row reverts and the
  next request executes again.
- **Handler returned 4xx** → response IS cached and replayed.
  This is intentional: a deterministic 4xx (e.g. "amount
  exceeds daily cap") should not flip to 2xx on retry.

## Client guidance

Mobile app and portal both:

1. Generate one UUID v4 per **user intent**, not per HTTP
   attempt. Persist it (Drift table on mobile, sessionStorage
   on portal) for the duration of the retry budget.
2. Send it as `Idempotency-Key` header. Body field is reserved
   for fallback when proxies strip the header.
3. On `409 IDEMPOTENCY_KEY_INFLIGHT` back off 1 s, 2 s, 4 s
   (max 3 attempts) before surfacing an error to the user.
4. On `409 IDEMPOTENCY_KEY_CONFLICT` (different body, same
   key) the user changed parameters mid-retry — surface the
   error and ask them to confirm again.

## CI guard (planned)

A future CI check `audit:idempotency-coverage` will scan
`portal/src/app/api/**` for any route with a SECURITY DEFINER
RPC call that mutates `coin_ledger`, `custody_*`, `wallets` or
`platform_revenue` and assert it is wrapped with
`withIdempotency()`. Tracked as a follow-up to L14-07.
