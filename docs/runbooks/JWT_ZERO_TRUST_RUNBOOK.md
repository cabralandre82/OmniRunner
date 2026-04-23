# JWT zero-trust runbook (L10-07)

> **Linked finding:** [`L10-07`](../audit/findings/L10-07-zero-trust-entre-microservicos-edge-functions-confiam-no.md)
> **Owner:** Platform / Security
> **CI check:** `npm run audit:jwt-claims-validation`
> **Test suite:** `npx tsx tools/test_l10_07_jwt_claims_validation.ts`

## 1. Why this exists

Before this fix, every Supabase Edge Function trusted _any_ JWT that
passed `auth.getUser()`. The function layer verified the signature but
did **not** enforce:

- `iss` — the issuer URL, so a token minted by a different Supabase
  project or a leaked anon key from another tenant could be replayed
  here.
- `aud` — the audience claim. Any token with `aud=authenticated` was
  accepted by any function: mobile, portal, custody, platform admin
  all looked identical to the gateway.
- The **client surface** actually invoking the route. A mobile JWT
  could call platform-admin endpoints as long as the caller knew the
  URL; ditto for a portal JWT hitting custody/withdraw.

That is the textbook confused-deputy / missing zero-trust control the
CSO lens flagged as **high severity**.

## 2. What we shipped

All the gates live in a single shared module:
`supabase/functions/_shared/auth.ts`. Every existing Edge Function
(43+ of them) already calls `requireUser()`, so _activating_ the new
defences means extending that helper (no per-function migration).

### 2.1 Defaults (applied to every caller automatically)

1. `iss` must equal one of the values in
   `AUTH_JWT_EXPECTED_ISSUERS` (comma-separated env). When unset the
   default is `${SUPABASE_URL}/auth/v1` — i.e. only tokens minted by
   _this_ Supabase project are accepted.
2. `aud` must intersect with `AUTH_JWT_ALLOWED_AUDIENCES` (env). When
   unset the default is `authenticated` (the Supabase default).
3. Violations raise `AuthError(403)` with a machine-readable `reason`:
   - `missing_bearer` · `invalid_jwt` · `malformed_jwt`
   - `invalid_issuer` · `missing_audience` · `audience_mismatch`
   - `client_mismatch` · `auth_service_unavailable` · `missing_env`

The JSON response exposed to the client includes `{error, reason}` so
observability dashboards can split 403s by root cause.

### 2.2 Opt-in tightening per route

High-value routes should tighten the contract via
`RequireUserOptions`:

```ts
// supabase/functions/challenge-withdraw/index.ts
const { user, db } = await requireUser(req, {
  allowedAudiences: ["omni-custody"],
  allowedClients: ["mobile", "portal"],
});
```

- `allowedAudiences` **replaces** the env default for this route; pass
  `["omni-custody"]` to require a token that was issued with a
  custody-scoped audience (for JWTs minted by a future exchange flow).
- `allowedClients` requires the caller to send
  `x-omni-client: mobile | portal | staff | platform_admin | internal`.
  Missing/unrecognised values → 403 `client_mismatch`.

There is also `skipClaimsCheck: true` as an escape hatch for running
against legacy tokens during a rollout. The CI guard (§3) FAILS the
build if this flag ships, so it is only for interactive debugging.

## 3. Detection

| Signal                            | Where                                                    | Action                      |
| --------------------------------- | -------------------------------------------------------- | --------------------------- |
| Shared helper drift               | `npm run audit:jwt-claims-validation`                    | Restore the expected shape  |
| Foreign call of `auth.getUser`    | same CI check                                            | Route through `requireUser` |
| `skipClaimsCheck: true` committed | same CI check                                            | Remove and add a test       |
| Behavioural regression            | `npx tsx tools/test_l10_07_jwt_claims_validation.ts`     | Investigate test that broke |
| Production signal                 | Edge Function logs with `reason=invalid_issuer`/mismatch | Investigate per §4          |

The CI guard scans every `supabase/functions/*/index.ts` (64+ files)
and refuses to ship if:

- `_shared/auth.ts` no longer declares the required markers
  (`decodeJwtPayload`, `assertClaimsShape`, the env overrides, the
  four machine reasons, `x-omni-client`), **or**
- any non-shared function calls `auth.getUser` directly (bypassing
  the helper), **or**
- any non-shared function hardcodes `skipClaimsCheck: true`.

## 4. Playbooks

### 4.1 Rolling out a new expected issuer (staging→prod cutover)

1. In staging, set `AUTH_JWT_EXPECTED_ISSUERS` to the comma-separated
   list including the new issuer (e.g. during a project swap).
2. Deploy. Watch Edge Function logs for 48 h — any
   `reason=invalid_issuer` should be legitimate blockage of tokens
   minted against the old project, **not** organic traffic.
3. Once confirmed, drop the legacy issuer from the env var and
   redeploy.

### 4.2 Tightening a custody route

1. Add `allowedAudiences: ["omni-custody"]` and
   `allowedClients: ["mobile", "portal"]` to the route's
   `requireUser(...)` call.
2. Ship the client change that starts minting tokens with the new
   audience **before** enabling the server check — or ship both
   behind a killswitch.
3. Monitor 403 `audience_mismatch` / `client_mismatch` in Logflare;
   zero is the expected steady state post-cutover.

### 4.3 Investigating a 403 with `reason=invalid_issuer`

1. Pull the JWT from the user's request ID (careful: PII; use
   ops-only tooling).
2. Decode with `jwt.io` (header + payload only, never expose the
   signature).
3. Compare `payload.iss` against the current
   `AUTH_JWT_EXPECTED_ISSUERS`.
4. If the claim is legitimate but the env is stale → update env var.
   Else → the token is foreign; the block is correct.

### 4.4 Investigating a 403 with `reason=client_mismatch`

1. Identify the offending route and confirm its
   `allowedClients` contract in code.
2. Check the HTTP call: the request **must** send `x-omni-client`
   with one of the allowed values.
3. If the client emitted the header correctly, it was dropped by a
   proxy/CDN. Add the header to the allow-list in Cloudflare / the
   edge transform.
4. If it was truly absent, fix the client to emit the correct value.

## 5. Rollback

The failsafe has two layers:

- Per-deployment: revert the shared helper to its previous commit —
  all Edge Functions automatically return to the pre-L10-07 behaviour
  (no iss/aud enforcement). No database change is needed.
- Per-route: a broken tightening can be relaxed by removing
  `allowedAudiences`/`allowedClients` from the `requireUser(...)`
  call — the default envs still enforce the safe minimum.

In an incident, prefer relaxing a single route over a full rollback.

## 6. Related findings

- L10-08 — `audit_logs` append-only (forthcoming).
- L10-09 — anti credential stuffing. Pairs well with L10-07 because
  once the attacker is stopped by email-scoped throttling, any token
  they do exfiltrate still has to pass the aud/iss gate here.
- L07-04 — Strava OAuth state validation (forthcoming).
