# JWT Revocation Policy

**Status:** Ratified (2026-04-21)
**Owner:** security + platform
**Related:** L01-15, L10-14 (Refresh Token Rotation), L01-26
(membership cache invalidation)

## Question being answered

> "An `admin_master` account is compromised (or banned). The
> attacker still holds a valid JWT issued ≤ 1 h ago. Until the
> JWT expires, every request the attacker makes is **honored** by
> the middleware (because `getUser()` only validates the token,
> it doesn't check a revocation list). What's the SLA between
> 'security event detected' and 'attacker session is dead'?"

## Decision

**Two-layer revocation**, no `revoked_tokens` table.

### Layer 1 — Force refresh-token invalidation

When any of these events happens:

- A user is added to or removed from `coaching_members` with a
  staff role (`admin_master`, `coach`, `assistant`).
- A user's `profiles.platform_role` changes (specifically:
  promotion to or demotion from `admin`).
- A user is hard-banned (`profiles.banned_at IS NOT NULL`).
- Internal SOC fires the security funnel (manual SEV-1 page).

an **Edge Function `force-signout`** runs:

```ts
await supabaseAdmin.auth.admin.signOut(userId, "global");
```

This invalidates **every refresh token** the user holds. The
current JWT (access token) is still valid until its `exp`, but
when the client tries to refresh — at most 5 min later in the
mobile app, much sooner in the portal — refresh fails and the
session is wiped client-side.

### Layer 2 — Membership / role cache eviction (already exists)

When the same events fire, the L01-26 membership cache is
explicitly evicted:

```ts
evictMembership(userId);
evictPlatformRole(userId);
```

Effect: even if the attacker still holds a valid JWT, the
**next** request goes back to the database for `coaching_members`
/ `platform_role`. The DB row is now gone (or downgraded), so
the middleware returns 403 / redirects to `/`.

## Why no `revoked_tokens` table

We considered the "Clinipharma reference" approach — a
`revoked_sessions(jti_hash text PRIMARY KEY, revoked_at)` table
checked in middleware. We rejected it for three reasons:

1. **Per-request DB hit on a hot path.** Every authenticated
   request would do an extra `SELECT 1 FROM revoked_sessions`
   (cacheable, but still operational complexity). Supabase JWTs
   don't carry a `jti` claim by default — we'd have to mint our
   own and re-issue them, which is a much larger surgery.
2. **Layer 2 already kills the attacker for `/platform/*` and
   for any group-scoped surface.** The remaining attack surface
   is "endpoints that only check `getUser()` returned a row,
   without checking role/membership." Those are: `/api/account/*`
   (self-data) and a handful of read-only endpoints. The blast
   radius of "attacker can read their own profile for ≤ 1 h" is
   acceptable.
3. **Refresh-token revocation is industry standard.** It's the
   pattern Supabase, Auth0, Clerk, Cognito and Stripe all
   recommend. Token-blacklisting tables are an anti-pattern at
   this scale.

## Effective worst-case window

| Surface                       | Worst-case attacker access |
|-------------------------------|----------------------------|
| `/api/platform/*`             | 0 s (cache evicted, DB row gone → 403 next request) |
| `/platform/*` (RSC)           | 0 s (same)                 |
| Group-scoped `/api/*`         | 0 s (membership cache evicted, DB downgrade → 403) |
| Self-data `/api/account/*`    | ≤ 5 min (mobile refresh) / ≤ 60 min (web JWT exp) |
| Read-only public-prefix       | n/a (no auth required)     |

For self-data the worst-case window is bounded by the access
token TTL (3600 s portal, 300 s mobile) — see L10-14 for those
settings.

## Implementation status

- **Spec:** ratified in this document. (L01-15)
- **`force-signout` Edge Function:** to be implemented in a
  follow-up PR (`security/force-signout`).
- **Cache eviction hooks:** already wired in
  `portal/src/lib/auth/membership-cache.ts` and
  `portal/src/lib/auth/platform-role-cache.ts`. Triggered by:
  - Server actions that mutate `coaching_members`.
  - `POST /api/platform/admins` (platform_role change).
  - The forthcoming `POST /api/platform/users/[id]/ban` endpoint
    (also calls `force-signout`).

## Test plan (follow-up PR)

1. Create a staff user → cache `coaching_members` membership →
   demote to `athlete` via SQL → assert next middleware call
   redirects to `/select-group` (not `/platform`).
2. Same flow but call `force-signout` → assert refresh fails on
   the next `auth.refreshSession()` from the client.
3. SOC SEV-1 simulation: trigger `force-signout` for an
   arbitrary user → assert all sessions across devices die
   within 5 min.

## See also

- `docs/security/REFRESH_TOKEN_ROTATION.md` (L10-14)
- `portal/src/lib/auth/membership-cache.ts` (L01-26)
- `portal/src/lib/auth/platform-role-cache.ts` (L01-26)
