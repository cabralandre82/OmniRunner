# CSRF Runbook (L01-06)

Operational guide for the cookie + CSRF-token defence that protects the
portal's financial mutation surface. Covers the **double-submit token**
implemented in `portal/src/lib/api/csrf.ts` and the
**`sameSite: "strict"`** session cookies in
`portal/src/lib/route-policy.ts`.

> Audience: portal on-call when triaging unexpected `403
> CSRF_TOKEN_INVALID` responses, or when adding a new mutation
> endpoint that should be CSRF-gated. Read time ~ 5 min.

## Architecture — 30-second recap

```
   ┌──────────┐   1. Browser navigates to any authenticated portal page
   │  Browser │
   └─────┬────┘
         │
         ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ middleware.ts                                                │
   │  ─ ensureCsrfCookie()  → mints `portal_csrf` if absent       │
   │     (32 bytes hex, sameSite=strict, httpOnly=false, secure)  │
   │  ─ shouldEnforceCsrf(method, path)                           │
   │     ─ true  → verifyCsrf() → 403 on mismatch                 │
   │     ─ false → pass through                                    │
   └──────────────────────────────────────────────────────────────┘
         │
         ▼
   ┌──────────┐   2. Client JS reads `portal_csrf` cookie via
   │  React   │      `csrfFetch()` and copies it to the
   │  page    │      `x-csrf-token` request header.
   └─────┬────┘
         │
         ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ Route handler  (only reached when verifyCsrf() returned ok) │
   └──────────────────────────────────────────────────────────────┘
```

## 1.0 Threat model addressed

| Vector                                                       | Mitigation              |
|--------------------------------------------------------------|-------------------------|
| Cross-site `<a href="https://portal/api/swap">` GET nav      | `sameSite: "strict"` on `portal_group_id` / `portal_role` (cookie not sent) |
| Cross-site `<form method=POST action="https://portal/...">`  | CSRF token: cookie not readable by attacker origin → header cannot be forged |
| Same-origin XSS forging the header                           | **NOT addressed here** — fix is CSP `unsafe-inline` removal (Lente 20.x) |
| Subdomain takeover writing to parent-domain cookie           | **NOT addressed here** — `path=/` only; needs HSTS + DNS hygiene |

## 2.0 What runs where

### 2.1 Server (middleware + helpers)
- `lib/api/csrf.ts` — pure helpers + verifier. Tested by
  `csrf.test.ts` (21 tests).
- `middleware.ts` — calls `shouldEnforceCsrf` + `verifyCsrf` BEFORE
  auth (cheap, denies attacker traffic without a Postgres round-trip)
  and `ensureCsrfCookie` AFTER successful session resolution.
- `lib/actions.ts → signOut` — deletes `portal_csrf` so the next user
  doesn't inherit the previous token.

### 2.2 Browser (UI components)
- `lib/api/csrf-fetch.ts → csrfFetch(url, init)` — drop-in `fetch`
  replacement. Auto-injects `x-csrf-token` from the cookie.
- All financial / platform-admin mutation buttons call `csrfFetch`,
  not `fetch`. Currently:
  - `(portal)/fx/withdraw-button.tsx`
  - `(portal)/athletes/distribute-button.tsx`
  - `(portal)/custody/deposit-button.tsx`
  - `(portal)/swap/swap-actions.tsx`
  - `platform/feature-flags/feature-flag-row.tsx`
  - `platform/fees/fee-row.tsx`
  - `platform/reembolsos/actions.tsx`

## 3.0 Adding a new gated endpoint

If you ship a new financial / platform mutation route, you must:

1. **Server side** — add the route's prefix to
   `CSRF_PROTECTED_PREFIXES` in `lib/api/csrf.ts`. The list is an
   **allow-list** by design: opting in is explicit, so reviewers
   immediately see the new security boundary.
2. **Client side** — call `csrfFetch` (NOT raw `fetch`) from the UI
   component issuing the POST.
3. **Test** — add a case to `csrf.test.ts → shouldEnforceCsrf` that
   asserts the new prefix returns `true`.

Webhook / external-callback endpoints (HMAC-authed callers) go in
`CSRF_EXEMPT_PREFIXES` instead — they're servers, not browsers, and
have no cookie store.

## 4.0 Triage: 403 CSRF_TOKEN_INVALID in production

The error response shape is:

```json
{
  "ok": false,
  "error": {
    "code": "CSRF_TOKEN_INVALID",
    "message": "...",
    "request_id": "<uuid>",
    "details": { "reason": "<sub-code>" }
  }
}
```

The `details.reason` sub-code disambiguates root cause:

| Sub-code              | Meaning                                              | Likely cause                                                           |
|-----------------------|------------------------------------------------------|------------------------------------------------------------------------|
| `CSRF_COOKIE_MISSING` | Request had no `portal_csrf` cookie                  | First-time visitor still on `/login`; or cookie was just deleted by `signOut` and the page wasn't reloaded |
| `CSRF_HEADER_MISSING` | Cookie present but no `x-csrf-token` header         | Caller used raw `fetch` instead of `csrfFetch` (bug — fix the call site); or third-party tool replaying captured POSTs |
| `CSRF_TOKEN_MALFORMED`| Cookie or header isn't 64 hex chars                  | Stale cookie from before L01-06; or attacker probing                  |
| `CSRF_TOKEN_MISMATCH` | Both well-formed, values differ                      | Stale tab after sign-out + sign-in as different user; or genuine attack — check IP / UA |

### 4.1 User-reported "I clicked the button and got an error"
1. Ask them to **hard-reload the page** (Ctrl-Shift-R). 99% of cases:
   the cookie was rotated by a sign-out and the open tab still had the
   old in-memory copy.
2. If it persists after reload, check `request_id` in Sentry / log
   shipper for the structured error envelope. The sub-code tells you
   which class of bug to chase.
3. If multiple users hit it on the same route, suspect a recent UI
   commit replaced `csrfFetch` with raw `fetch` —
   `git grep -n "fetch(\"/api/" portal/src/app` and check the call
   sites against the gated prefix list.

### 4.2 Spike of CSRF_TOKEN_MISMATCH from a single IP
Likely a CSRF probe. The token comparison is constant-time so the
probe yields no signal — but log the IP and consider rate-limiting at
the WAF tier if it's sustained.

### 4.3 Token issuance broken (everyone fails after deploy)
Symptoms: 403 `CSRF_COOKIE_MISSING` rate jumps to 100 % of POSTs
after a deploy.

1. `git diff HEAD~1 -- portal/src/middleware.ts` — did the
   `ensureCsrfCookie` call get removed from the relevant branch?
2. Verify in dev: open `chrome://settings/cookies`, filter by the
   portal domain, confirm `portal_csrf` is in the jar after a fresh
   login.
3. Worst-case rollback: `git revert <bad-commit>` — the CSRF
   subsystem is one commit + dedicated to one concern, so reverting
   is safe.

## 5.0 Rotating the token

### 5.1 Voluntary rotation (suspected leak)
There is no "rotate all tokens" admin button — each token is bound to
one cookie jar in one browser. To force rotation for a single user,
have them sign out + sign back in (the `signOut` action deletes
`portal_csrf`).

To force rotation **globally** (e.g. after a confirmed XSS that may
have leaked tokens), bump the `CSRF_COOKIE_NAME` constant in
`lib/api/csrf.ts` to `portal_csrf_v2`. All existing cookies become
unrecognised → next request mints a fresh `v2` token. Schedule the
rename + deploy in a low-traffic window so users see one extra
"please reload" prompt instead of a sustained error rate.

### 5.2 Sign-out flow (already automatic)
`signOut` in `lib/actions.ts` deletes `portal_csrf` alongside
`portal_group_id` / `portal_role` / Supabase auth cookies. No manual
intervention required.

## 6.0 Why these design choices

- **Allow-list, not block-list.** Forcing a developer to add a route
  to `CSRF_PROTECTED_PREFIXES` makes the security posture greppable
  and code-reviewable.
- **CSRF check before auth.** Pure-function comparison costs ~15 µs;
  doing it after the Supabase round-trip would let an attacker burn
  Postgres IO at request rate.
- **`httpOnly: false` is intentional.** Required for the double-
  submit pattern. The token is NOT a credential by itself — it only
  proves the request came from a script that shares the user's
  origin. Same-origin XSS can read it, but same-origin XSS can also
  read every other cookie in the jar; CSRF cannot defend against XSS,
  CSP can.
- **`sameSite: "strict"` UX cost.** External deep-links to the portal
  (Slack, email, Sentry) arrive without `portal_group_id` and bounce
  through `/select-group`. One extra click. Acceptable trade for
  closing the lax-cookie GET-navigation CSRF vector.
