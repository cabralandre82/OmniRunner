# CSRF Runbook (L01-06 + L17-06)

Operational guide for the layered CSRF defence on the portal:

1. **Origin pinning (L17-06)** — every `/api/*` mutating request that
   isn't in `CSRF_EXEMPT_PREFIXES` must arrive with an `Origin` (or
   fallback `Referer`) host equal to the request host. Default-on for
   the entire mutating API surface; closes the gap "non-financial
   routes had zero CSRF gate".
2. **Double-submit token (L01-06)** — financial / platform-admin
   routes additionally require an `x-csrf-token` header that matches
   the `portal_csrf` cookie. Defence in depth on top of (1).
3. **`sameSite: "strict"` session cookies** — `portal_group_id` /
   `portal_role` (`portal/src/lib/route-policy.ts`) never cross
   origins, so even before (1) and (2) the lax-cookie navigation
   CSRF vector is dead.

> Audience: portal on-call when triaging unexpected `403
> CSRF_ORIGIN_INVALID` / `CSRF_TOKEN_INVALID` responses, or when
> adding a new mutation endpoint. Read time ~ 7 min.

## Architecture — 30-second recap

```
   ┌──────────┐   1. Browser navigates to any authenticated portal page
   │  Browser │
   └─────┬────┘
         │
         ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ middleware.ts                                                │
   │                                                              │
   │  L17-06  shouldEnforceOrigin(method, path) ─┐                │
   │              ─ true  → verifyOrigin()       │                │
   │                       ─ ok       → continue │ (cheap; pure)  │
   │                       ─ mismatch → 403      │                │
   │              ─ false → skip (exempt prefix) │                │
   │                                              ▼               │
   │  L01-06  shouldEnforceCsrf(method, path)                     │
   │              ─ true  → verifyCsrf() → 403 on mismatch        │
   │              ─ false → pass through                          │
   │                                                              │
   │  L01-06  ensureCsrfCookie()  → mints `portal_csrf` if absent │
   │            (32 bytes hex, sameSite=strict, httpOnly=false,   │
   │             secure)                                          │
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
   │ Route handler  (only reached when both gates returned ok)   │
   └──────────────────────────────────────────────────────────────┘
```

## 1.0 Threat model addressed

| Vector                                                                  | Mitigation              |
|-------------------------------------------------------------------------|-------------------------|
| Cross-site `<a href="https://portal/api/swap">` GET nav                 | `sameSite: "strict"` on `portal_group_id` / `portal_role` (cookie not sent) |
| Cross-site `<form method=POST action="https://portal/...">`             | **L17-06 origin pinning** — Origin host ≠ request host → 403 BEFORE the route handler runs (no client opt-in needed) |
| Cross-site fetch with `mode: "no-cors"` POST (form-encoded)             | Origin pinning rejects (browser sends Origin on every cross-origin POST including no-cors) |
| Cross-site fetch from same SLD via subdomain takeover                   | L17-06 origin host equality is *exact* — `evil.portal.com` ≠ `portal.com` |
| Cross-site fetch on a financial route                                   | Origin pinning **AND** double-submit token — attacker would also need to forge the `x-csrf-token` header, which requires reading the cookie (blocked by browser same-origin policy) |
| Same-origin XSS forging both Origin and the header                      | **NOT addressed here** — fix is CSP `unsafe-inline` removal (Lente 20.x) |
| Subdomain takeover writing to parent-domain cookie                      | **NOT addressed here** — `path=/` only; needs HSTS + DNS hygiene |

## 2.0 What runs where

### 2.1 Server (middleware + helpers)
- `lib/api/csrf.ts` — pure helpers + verifiers (`shouldEnforceOrigin`,
  `verifyOrigin`, `shouldEnforceCsrf`, `verifyCsrf`,
  `ensureCsrfCookie`, `clearCsrfCookie`). Tested by `csrf.test.ts`
  (36 tests covering both gates).
- `middleware.ts` — runs in this order on every `/api/*` mutating
  request:
  1. `verifyOrigin` (L17-06) — broad gate, default-on
  2. `verifyCsrf` (L01-06) — narrow allow-list of financial routes
  3. session / membership resolution
  4. `ensureCsrfCookie` (mints `portal_csrf` if absent on the response)
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

## 3.0 Adding a new mutation endpoint

### 3.1 Browser-driven mutation (the common case)
If the new route is called from the portal UI by a logged-in user via
`fetch()` or `csrfFetch()`, **you don't need to do anything** to opt
into origin pinning — `shouldEnforceOrigin` defaults to `true` for
every `/api/*` non-safe method. Just verify your client sends a same-
origin POST (it always will, unless you've configured an exotic CORS
proxy).

If the route handles **money / refunds / feature flags / fees /
custody**, also opt into the token gate:

1. Add the route prefix to `CSRF_PROTECTED_PREFIXES` in
   `lib/api/csrf.ts`. The token gate is an **allow-list** by design:
   opting in is explicit, so reviewers see the new security boundary.
2. Migrate the client component to `csrfFetch` (NOT raw `fetch`).
3. Add a case to `csrf.test.ts → shouldEnforceCsrf` that asserts the
   new prefix returns `true`.

### 3.2 Server-to-server / webhook / cron endpoint
If the route is hit by an external scheduler or HMAC-authed third
party (Asaas / Stripe / Vercel Cron / pg_net), add its prefix to
`CSRF_EXEMPT_PREFIXES` in `lib/api/csrf.ts`. Each existing entry has
a justification comment — yours must too. Then make sure the route
handler does its own authentication (HMAC signature, OAuth `state`,
or `CRON_SECRET` constant-time compare) — origin pinning will NOT
fire and you cannot fall back on it.

### 3.3 Browser-pushed report endpoint (CSP / NEL / RUM)
If the route receives unauthenticated browser-issued reports (e.g.
`/api/csp-report`), add it to `CSRF_EXEMPT_PREFIXES`. Browsers send
these with `Origin: null` from sandboxed contexts. The route handler
must rate-limit and cap body size since it's now reachable without
a CSRF gate.

## 4.0 Triage: 403 CSRF_*_INVALID in production

The error response shape is uniform across both gates:

```json
{
  "ok": false,
  "error": {
    "code": "CSRF_ORIGIN_INVALID" | "CSRF_TOKEN_INVALID",
    "message": "...",
    "request_id": "<uuid>",
    "details": { "reason": "<sub-code>" }
  }
}
```

`error.code` tells you which **gate** rejected; `details.reason` is
the gate-specific sub-code below.

### 4.1 `CSRF_ORIGIN_INVALID` (L17-06 gate)

| Sub-code                | Meaning                                                | Likely cause |
|-------------------------|--------------------------------------------------------|--------------|
| `ORIGIN_HOST_MISSING`   | No `Host` header on incoming request                   | Middlebox stripping headers; almost always a misconfigured proxy |
| `ORIGIN_HEADER_MISSING` | Neither `Origin` nor `Referer` present                 | Server-to-server caller hit a non-exempt route — add the prefix to `CSRF_EXEMPT_PREFIXES` if legitimate; otherwise an attacker stripping headers |
| `ORIGIN_NULL`           | `Origin: null` (sandbox iframe / file://)              | Sandboxed embed POSTing to the API; legitimate cases are extremely rare and should be carved out explicitly per-route |
| `ORIGIN_MALFORMED`      | Origin/Referer not a valid absolute URL                | Almost always a buggy custom HTTP client; or fingerprint probe |
| `ORIGIN_HOST_MISMATCH`  | Host(Origin) ≠ Host(request)                           | Either a cross-origin attacker page, OR the portal is sitting behind a misconfigured proxy that rewrites `Host` but not `Origin`. Verify the proxy's host-header policy. |

### 4.2 `CSRF_TOKEN_INVALID` (L01-06 gate)

| Sub-code              | Meaning                                              | Likely cause                                                           |
|-----------------------|------------------------------------------------------|------------------------------------------------------------------------|
| `CSRF_COOKIE_MISSING` | Request had no `portal_csrf` cookie                  | First-time visitor still on `/login`; or cookie was just deleted by `signOut` and the page wasn't reloaded |
| `CSRF_HEADER_MISSING` | Cookie present but no `x-csrf-token` header         | Caller used raw `fetch` instead of `csrfFetch` (bug — fix the call site); or third-party tool replaying captured POSTs |
| `CSRF_TOKEN_MALFORMED`| Cookie or header isn't 64 hex chars                  | Stale cookie from before L01-06; or attacker probing                  |
| `CSRF_TOKEN_MISMATCH` | Both well-formed, values differ                      | Stale tab after sign-out + sign-in as different user; or genuine attack — check IP / UA |

### 4.3 Metrics

Both gates emit structured counters that aggregate by sub-code:

- `csrf.origin_blocked{reason=ORIGIN_HOST_MISMATCH|ORIGIN_NULL|...}`
- `csrf.token_blocked{reason=CSRF_TOKEN_MISMATCH|...}`

A spike in `csrf.origin_blocked{reason=ORIGIN_HEADER_MISSING}` after a
deploy almost always means a new server-to-server caller was added
without updating `CSRF_EXEMPT_PREFIXES`. A spike in
`csrf.origin_blocked{reason=ORIGIN_HOST_MISMATCH}` from a single IP is
an attack signal.

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

- **Two gates, two policies.** Origin pinning is **default-deny**
  (every `/api/*` mutating route is gated unless explicitly exempt)
  because the check is free for legitimate browser callers — modern
  browsers always send `Origin` on POST/PUT/PATCH/DELETE. Token
  gate is **allow-list** (only the financial routes opt in) because
  it requires the client to call `csrfFetch`, and forcing every UI
  to migrate before a single line of CSRF protection ships would have
  delayed the L01-06 fix indefinitely. The two compose: financial
  routes get both layers, the rest gets just origin pinning.
- **L17-06 shipped without breaking any existing client.** Origin
  pinning works on raw `fetch()` calls because browsers attach the
  `Origin` header automatically. The migration path "add a token gate
  to a route" is now strictly additive — origin pinning never has to
  be turned off to roll out a new endpoint.
- **CSRF checks before auth.** Pure-function comparison costs ~15 µs;
  doing them after the Supabase round-trip would let an attacker burn
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
- **Scheme-agnostic origin compare.** Behind a TLS-terminating proxy
  the internal request often arrives as `http://` even when the
  browser sent `https://`. CSRF cares about *host equality*; HSTS +
  the `secure` cookie flag own the scheme guarantee. Comparing scheme
  here would manufacture false 403s on every TLS-terminated deploy.
