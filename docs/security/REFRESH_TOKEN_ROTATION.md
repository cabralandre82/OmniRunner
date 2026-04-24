# Supabase JWT + refresh-token rotation policy (L10-14)

> **Status:** ratified · **Owner:** Security + Platform · **Last updated:** 2026-04-21

## TL;DR

* `Refresh Token Rotation` = **ON** (Supabase Dashboard →
  Auth → Settings → JWT).
* `Reuse Interval` = **0 seconds** (no grace; reuse triggers
  full re-auth).
* `Rotation Period` = **10 seconds** (window during which the
  Supabase client may swap a refresh token for a new pair).
* `JWT Expiry` = **3600 seconds** (1 h access token).
* `Refresh Token Expiry` = **2592000 seconds** (30 d).
* CI: `audit:jwt-claims-validation` (existing) + a new
  `audit:supabase-auth-config` (CI guard described below) that
  reads the deployed config via the Management API and fails
  the build on drift.

## Why these values

* **Rotation ON, Reuse Interval 0** — every refresh swap
  invalidates the old token immediately. If a stolen refresh
  token is used after the legitimate user has refreshed, the
  reuse triggers a SECURITY event (`refresh_token_reused`) in
  the Supabase audit log, which we ingest into our `audit_logs`
  table via the existing webhook ingestor (L18-09) and page
  the on-call.
* **10-second rotation period** — wide enough to absorb
  network jitter; narrow enough that a stolen token without
  the legitimate device's session would have already expired
  in the typical attack window.
* **1-hour JWT** — short enough that a stolen access token is
  a 1-h window; long enough that mobile users on flaky 3G
  don't auth-thrash.
* **30-day refresh** — matches the "stay signed in" UX
  expectation. Forced re-auth cadence is therefore monthly
  for inactive users, immediate for any device that drops the
  refresh token (Flutter secure storage corruption, manual
  logout, etc.).

## How rotation actually works

```
client (mobile / portal)                       Supabase Auth
─────────────────────                          ────────────
  GET /workouts                                  …
   │
   ├── Authorization: Bearer <access_token>     valid until exp
   │
   └─ access_token expires (every 1h) ───┐
                                          ▼
                              POST /auth/v1/token?grant_type=refresh_token
                              { refresh_token: <old_rt> }
                                          │
                              ┌───────────┴───────────┐
                              │ rotate? (yes)         │
                              │ invalidate <old_rt>   │
                              │ issue <new_at, new_rt>│
                              └───────────┬───────────┘
                                          ▼
                              { access_token: <new_at>,
                                refresh_token: <new_rt> }
   │
   └─ store new pair atomically; replay if mid-flight requests fail
```

If a second request arrives at Supabase Auth with the same old
`<old_rt>`:

```
                              POST /auth/v1/token?grant_type=refresh_token
                              { refresh_token: <old_rt> }
                                          │
                                          ▼
                              { error: refresh_token_reused }
                              + Supabase audit log row:
                                action = 'token_reuse_detected'
                                user_id = <victim>
                              + ALL of <victim>'s sessions
                                are revoked.
```

That last bullet is the critical defence. Once a reuse is
detected, every active session for the user is killed, forcing
the (legitimate or attacker) device to re-auth with email/OTP/
oauth — which the attacker presumably cannot.

## Configuration verification

The settings live in three places and MUST match:

1. **Supabase Dashboard** (the runtime source of truth).
2. **`docs/security/REFRESH_TOKEN_ROTATION.md`** (this file).
3. **`docs/runbooks/SUPABASE_AUTH_BOOTSTRAP.md`**
   (recreate-from-scratch runbook).

Drift is caught by an upcoming CI guard
`tools/audit/check-supabase-auth-config.ts` (planned), which
issues a `GET /v1/projects/{ref}/config/auth` against the
Management API with a read-only PAT and asserts:

```json
{
  "JWT_EXP": 3600,
  "REFRESH_TOKEN_ROTATION_ENABLED": true,
  "SECURITY_REFRESH_TOKEN_REUSE_INTERVAL": 0
}
```

Until the Management-API guard ships, the policy is enforced
manually during the quarterly secret-rotation review (see
`docs/runbooks/SECRET_ROTATION_RUNBOOK.md`).

## Client requirements

Both `@supabase/supabase-js` (portal) and `supabase_flutter`
(mobile) ship with refresh-rotation aware token storage. The
mobile app uses `flutter_secure_storage` (hardened in L01-28
and L11-14); the portal uses `cookies()` with the
`@supabase/ssr` cookie helpers.

Both clients RACE protect their refresh swap with a per-process
mutex (the SDK does this internally). Custom workers (e.g.
the `revoke-integrations` Edge Function) MUST use the SDK and
NOT hand-roll a refresh call.

## Incident response

When `refresh_token_reused` fires:

1. Webhook ingestor adds a row to `audit_logs` with
   `event_domain = 'auth'` and `action =
   'token_reuse_detected'` (L18-09).
2. The `auth.alerts.token_reuse` Sentry rule fires a P2 alert
   to the on-call.
3. The on-call:
   * Confirms the user's IP / UA mismatch in the audit log.
   * If suspicious, follows the `account-takeover` playbook
     (`docs/runbooks/ACCOUNT_TAKEOVER.md`, planned for K7).
   * If benign (same UA, normal IP — usually a clock-drift
     device), notes it in the per-quarter false-positive
     tally; > 5 FP/quarter triggers a re-evaluation of the
     reuse interval.

## Cross-references

* L01-15 — JWT expiry window / forced logout
* L01-19 — Edge Function `verify_jwt = false` audit
* L05-15 — mobile logout revoke (forced disconnect on funnel)
* `docs/runbooks/MOBILE_LOGOUT_REVOKE_OAUTH.md`
* `docs/runbooks/SECRET_ROTATION_RUNBOOK.md`
