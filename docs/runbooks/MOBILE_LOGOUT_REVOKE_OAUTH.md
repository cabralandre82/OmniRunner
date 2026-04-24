# Mobile logout — revoke OAuth integrations (L05-15)

> **Status:** spec ratified · **Owner:** Mobile + Integrations · **Last updated:** 2026-04-21

## Problem

The mobile "Sair" button in `profile_screen.dart` calls
`Supabase.auth.signOut()` and clears the local session, but the
`refresh_token` we hold for **Strava** and **TrainingPeaks** stays
in the `strava_connections` / `tp_connections` Supabase tables. The
next time the same user logs in we silently rehydrate the
integration without re-prompting. Users — reasonably — expect
"logout = unhook everything".

## Decision

Logout always offers a one-tap **disconnect-all** option. Default
posture is **opt-in**: integrations stay attached unless the user
asks otherwise, because:

* the most common reason to log out is "switching device" — the
  user wants the connection to follow them,
* re-authorising Strava/TP is friction the user did not pay before
  on competitor apps.

A second flow — **forced** disconnect — runs whenever logout is
triggered by the security funnel (account compromise reset, password
change, new-device review). That flow does NOT ask, it simply
revokes everything.

## UI contract

The logout sheet shows three buttons in this order:

```
┌────────────────────────────────────────┐
│  Sair desta sessão                     │  ← default; preserves all connections
│                                        │
│  Sair e desconectar                    │
│  apps conectados                       │  ← shows N integrations chip ("Strava, TP")
│                                        │
│  Cancelar                              │
└────────────────────────────────────────┘
```

The chip enumerates the active integrations queried from
`strava_connections` and `tp_connections` at sheet-open time. If
neither table returns a row, the second button is hidden — the user
has nothing to disconnect.

## Server-side flow

The disconnect path posts to a new RPC
`fn_revoke_user_integrations(user_id uuid, integrations text[])`
(`SECURITY DEFINER`, `SET search_path = public`). For each item:

| Integration   | Revocation endpoint                                       | Local cleanup                                                       |
|---------------|-----------------------------------------------------------|---------------------------------------------------------------------|
| `strava`      | `POST https://www.strava.com/oauth/deauthorize` w/ token  | `DELETE FROM strava_connections WHERE user_id = ?`                  |
| `trainingpeaks` | `POST https://oauth.trainingpeaks.com/oauth/revoke`     | `DELETE FROM tp_connections WHERE user_id = ?`                      |

The RPC is wrapped by an Edge Function `revoke-integrations` so the
HTTP calls happen off the request hot-path (Supabase RPCs are
synchronous and would otherwise block logout for ~1 s × N
integrations). The Edge Function:

1. accepts `{ user_id, integrations }` from the client (mobile must
   send a valid Supabase JWT — the function `verifies_jwt` and
   re-resolves `user_id` server-side, never trusts the body),
2. fans out to each provider's revoke endpoint with a 5 s timeout,
3. on timeout / non-2xx, queues a retry via `cron_edge_retry_attempts`
   so we eventually achieve revocation,
4. always deletes the local row even if the upstream revoke fails
   (a stale token is preferable to a stale connection that the user
   thought they killed).

## Auth + audit

Every revoke writes an `audit_logs` row with:

```
event_domain      = 'integration'
event_schema_version = 1
action            = 'integration.revoke.completed'
                  | 'integration.revoke.failed'
metadata.provider = 'strava' | 'trainingpeaks'
metadata.reason   = 'user_logout' | 'forced_disconnect' | 'admin_override'
```

This satisfies the L18-09 dotted-domain contract and is queryable
from the platform-admin support tooling.

## Future integrations

When we add Garmin Connect / Polar Flow / etc., extend the
`integrations` enum, the table-driven map above, and the chip in
the logout sheet. No new RPC needed.

## Cross-references

* `docs/audit/findings/L05-15-mobile-logout-nao-revoga-tokens-strava-trainingpeaks.md`
* `docs/audit/findings/L01-15-jwt-expiry-window-logout-forcado.md` (forced disconnect on
  security funnel)
* L18-09 — domain events in audit_log (event_domain naming)
* L06-05 — Edge retry wrapper (cron_edge_retry_attempts)
