# CSP Runbook (L01-38 / L10-05)

> **Owner:** portal-team · **Severity ladder:** P2 (single user / dev
> tooling) · P1 (XSS exploitation evidence in production)
>
> **Linked findings:** [L01-38] (`script-src 'unsafe-inline'`/`'unsafe-eval'`
> removed) · [L10-05] (CSP report-uri)
>
> **Source of truth:** `portal/src/lib/security/csp.ts` (builder),
> `portal/src/middleware.ts` (per-request emission),
> `portal/src/app/api/csp-report/route.ts` (violation sink).

This runbook covers the lifecycle of the portal Content-Security-Policy:
how it's built, how to tighten it further, what to do when it trips
in production, and how to roll back safely if a release breaks
legitimate inline-script behaviour.

---

## 1. What ships in production

A request to any portal route gets:

```
Content-Security-Policy: default-src 'self';
  script-src 'self' 'nonce-<base64>' 'strict-dynamic';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: blob: https://*.supabase.co;
  font-src 'self';
  connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.sentry.io;
  worker-src 'self' blob:;
  frame-ancestors 'none';
  base-uri 'self';
  form-action 'self';
  object-src 'none';
  upgrade-insecure-requests;
  report-uri /api/csp-report;
  report-to csp-endpoint
Report-To: {"group":"csp-endpoint","max_age":10886400,"endpoints":[{"url":"/api/csp-report"}],"include_subdomains":true}
```

Why this exact shape: see the JSDoc at the top of
`portal/src/lib/security/csp.ts` (every directive is justified
inline with reference to the threat model).

Development adds `'unsafe-eval'` to `script-src` (Next.js Fast
Refresh + React Refresh both compile via `new Function()`) and
`ws://localhost:*` + `http://localhost:*` to `connect-src` (HMR
transport). Production never carries those.

---

## 2. Adding a new inline script (or a new third-party origin)

1. **Default position: don't.** Inline `<script>` defeats the entire
   point of L01-38. If you need a one-off bootstrap, put it in a
   `.js` file under `public/` and reference it via `<script src="…">`.
   That's the path we used for Swagger UI's bootstrap
   (`portal/scripts/swagger-init.js` → copied to
   `public/vendor/swagger-ui/swagger-init.js` at build time).

2. **If inline is genuinely required** (e.g. JSON-LD, structured
   data), use the per-request nonce:

   ```tsx
   // RSC
   import { headers } from "next/headers";

   export default async function Page() {
     const nonce = (await headers()).get("x-nonce") ?? "";
     return (
       <script
         nonce={nonce}
         type="application/ld+json"
         dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
       />
     );
   }
   ```

   `'strict-dynamic'` means: once the nonce'd script runs, anything
   it dynamically injects is also trusted. So a Next.js chunk that
   was loaded under `'self'` can `import()` further chunks without
   each one needing its own nonce.

3. **New third-party origin** (e.g. analytics): edit
   `portal/src/lib/security/csp.ts`, add the host to the relevant
   directive (`script-src`, `connect-src`, `img-src`, …). The unit
   tests in `csp.test.ts` will fail if you accidentally add it to
   `script-src` *and* re-introduce `'unsafe-inline'` — that's the
   regression guard L01-38 was put in place to prevent.

4. **Verify in dev**: open DevTools → Network → click any document
   request → "Response Headers" should show the new
   `Content-Security-Policy` line. Reload the page and check the
   browser console for "Refused to load …" or "Refused to execute
   inline script…" entries — those will also be POSTed to
   `/api/csp-report` and surface in the server log + Sentry.

---

## 3. Symptom → diagnosis → fix matrix

### Symptom A: production page is blank, console shows
"Refused to execute inline script because it violates the following
Content Security Policy directive: script-src 'self' 'nonce-…'
'strict-dynamic'"

**Diagnosis:** a route or layout introduced an inline `<script>` tag
without a `nonce` attribute (or with a stale nonce from a prior
render). Common offenders:

- `next/script` with `strategy="beforeInteractive"` and an inline
  body — Next.js does NOT auto-inject the nonce; you have to read
  it from `headers().get("x-nonce")` and pass it explicitly.
- A library that injects `<script>document.write(…)</script>` at
  runtime (Google Tag Manager, Hotjar, etc.).
- `dangerouslySetInnerHTML` with HTML that contains `<script>…</script>`.

**Fix:**

1. Identify the culprit from the console message — it includes the
   first 40 chars of the offending source.
2. If it's our own code, refactor to either:
   - Move the body to a static file under `public/` and reference
     via `<script src="…">`, OR
   - Read `nonce = (await headers()).get("x-nonce")` in the RSC and
     pass it via `<script nonce={nonce}>`.
3. If it's a third-party widget that *requires* inline injection,
   evaluate alternatives first; if none, document the trade-off in
   `csp.ts` and add the specific origin to `script-src` (NEVER
   re-add `'unsafe-inline'` globally).

### Symptom B: dev mode broken with "Refused to evaluate string as
JavaScript because 'unsafe-eval' is not an allowed source of script"

**Diagnosis:** dev environment is wrongly building `isDev=false`.
Usually `NODE_ENV` ended up as something other than `development`
(common with `next start` instead of `next dev`).

**Fix:**

```bash
# Verify which env the middleware sees:
NODE_ENV=development npm run dev
# Check headers:
curl -I http://localhost:3000/ | grep -i content-security-policy
# Expect to see 'unsafe-eval' in script-src.
```

If you ARE running `next start` locally (production mode), accept
that you can't HMR — that's working as intended.

### Symptom C: `/api/csp-report` returning 4xx/5xx

**Diagnosis:** the report endpoint should always return 204 (even
on parse errors — see route docstring for why). 4xx/5xx means the
middleware bailed before the handler ran.

**Fix:**

```bash
# Check middleware order — /api/csp-report MUST be in PUBLIC_ROUTES
# (route-policy.ts) or auth will 401 the browser's report POST.
rg "csp-report" portal/src/lib/route-policy.ts
```

If missing, add it back to `PUBLIC_ROUTES`. Browsers send reports
with no cookies, so any auth gate silently drops them.

### Symptom D: Sentry being flooded with `csp.violation.script_src`

**Diagnosis:** a real CSP violation is firing on every page load.
This is THE event we built `/api/csp-report` to catch — treat it
as a P1 until proven otherwise.

**Fix:**

1. Open the Sentry issue. The `tags.csp_blocked_uri` and
   `extra.source_file` together identify which inline script tripped.
2. Determine: is this attacker activity (XSS attempt) or our own
   broken release?
   - **Attacker activity**: `blocked_uri` is something like
     `data:text/html,…` or an external host we don't recognise. The
     CSP blocked it — defensive posture worked. Investigate the
     injection vector (audit the route the report came from).
   - **Our own broken release**: `blocked_uri` is `inline` and
     `source_file` is one of our pages. A recent deploy reintroduced
     an inline script. Apply the fix from Symptom A and consider
     reverting if the regression rate is high.
3. Coarse rate limit (60 reports / 60 s / process) protects the
   Sentry quota, but volume above ~30/s sustained suggests every
   page load is tripping — escalate to a P1 page even if no
   exploitation evidence.

### Symptom E: report endpoint is silent (no logs, no Sentry hits)
even though we know the page has a CSP violation

**Diagnosis:** likely browser doesn't honour same-origin
`report-uri`. Some Safari versions enforce `report-uri` from
HTTPS only — local dev over HTTP won't report.

**Fix:**

- If reproducing locally over HTTPS via `mkcert`, this should work.
- In production over HTTPS, check the browser console first — if
  the browser logs a violation but no POST to `/api/csp-report`
  shows up in the Network tab, the `report-uri` directive itself
  is missing. Verify with:
  ```bash
  curl -I https://portal.omnirunner.app/ | grep -i content-security-policy
  # Expect: …; report-uri /api/csp-report; report-to csp-endpoint
  ```
- If absent, the middleware probably crashed before
  `tagResponse(...)`. Check application logs for the request id.

---

## 4. Rolling back the strict CSP

In an emergency where the strict CSP is blocking a critical user
flow and the proper fix is hours away, you can degrade gracefully:

1. **First-line mitigation: report-only mode.** Edit
   `portal/src/middleware.ts`, replace the
   `Content-Security-Policy` header with `Content-Security-Policy-
   Report-Only` (browser logs but does NOT block). This buys time
   while preserving observability.

   ```ts
   // TEMPORARY — restore this within 24h.
   res.headers.set("Content-Security-Policy-Report-Only", cspHeaderValue);
   ```

2. **Last-resort mitigation: re-add `'unsafe-inline'`.** Pass it as
   an additional `extraConnectSrc`-like override (currently NOT
   exposed; would need a one-line change to `csp.ts` to accept
   `extraScriptSrc`). DO NOT silently flip the production
   `isDev=true` switch — that re-enables `'unsafe-eval'` too,
   which is wider than needed.

3. **Whatever you do, file an incident.** L01-38 is a high-severity
   audit finding; rolling back the fix needs a P1 ticket and a
   target re-enforce date.

---

## 5. Testing changes locally

```bash
# Unit-test the builder (24 cases, deterministic):
cd portal && npx vitest run src/lib/security/csp.test.ts

# Unit-test the report endpoint (13 cases):
cd portal && npx vitest run src/app/api/csp-report/route.test.ts

# Smoke-test the assembled middleware response:
cd portal && npm run dev
curl -I http://localhost:3000/login | grep -iE "(content-security|report-to|x-request-id)"

# Force a violation to confirm the report endpoint works:
curl -X POST http://localhost:3000/api/csp-report \
  -H "content-type: application/csp-report" \
  -d '{"csp-report":{"document-uri":"http://localhost:3000/","violated-directive":"script-src","blocked-uri":"inline"}}'
# Expect: HTTP 204 + a JSON line in the dev server stdout
# (`csp.violation.script_src`).
```

---

## 6. Drill (quarterly)

1. Pick a random RSC and add an inline `<script>console.log(1)</script>`.
2. Deploy to staging.
3. Confirm:
   - Page renders but console shows CSP violation.
   - `/api/csp-report` POST appears in the Network tab.
   - Sentry receives a `csp.violation.script_src` warning within
     ≤ 60 s.
   - The on-call gets a Slack ping (`#incidents`) for the warning.
4. Revert the inline script. Confirm Sentry stops seeing reports
   within one cache TTL.
5. Postmortem the time-to-detect — should be ≤ 60 s end-to-end.
