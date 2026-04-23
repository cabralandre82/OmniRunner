# EMAIL TRANSACTIONAL RUNBOOK — L15-04

> **Audit refs:** L15-04 · [`docs/audit/findings/L15-04-sem-email-transactional-platform.md`](../audit/findings/L15-04-sem-email-transactional-platform.md) · anchor `[15.4]` in [`docs/audit/parts/06-middleware-contracts-cmo-cao.md`](../audit/parts/06-middleware-contracts-cmo-cao.md)
> **Status:** fixed (2026-04-21)
> **Owner:** platform
> **Related:** L12-09 (notification idempotency), L10-09 (credential stuffing — email verification), L04-07 (ledger PII), L18-04 (idempotency_keys), L15-03 (cost observability)

---

## 1. Why this exists

The CMO audit ran `grep 'resend|postmark|sendgrid|mailgun' portal/src supabase/functions` and found **zero** matches. Before this PR, every "your withdraw was processed", "payment confirmed — R$ 49,90", coaching invite, and championship invite email our product copy claimed we sent either (a) never left the server because no provider was wired, or (b) leaked out via Supabase Auth's default SMTP — which is unconfigured here, shares the same hosted quota (2 emails/hour/user per `auth.rate_limit.email_sent` in [`supabase/config.toml`](../../supabase/config.toml)) as login confirmations, and has no delivery audit trail. Turning on `enable_confirmations = true` for L10-09 anti-credential-stuffing would have pushed the quota into saturation within minutes.

The platform delivers three properties the old stack lacked:

1. **Every transactional email lands in `public.email_outbox` first** — one row per delivery lifecycle, keyed by a caller-supplied `idempotency_key`. Replaying the same RPC call returns the same row; you cannot accidentally double-send a receipt.
2. **Provider is swappable via `EMAIL_PROVIDER` env** — `resend` in prod, `inbucket` for `supabase start`, `null` for CI / sandbox (default). Callers never see the provider; they call `sendEmail()` and read back `{ status, provider, providerMessageId, error }`.
3. **Templates are versioned on disk + registered in a manifest** — `supabase/email-templates/*.html` is the source of truth; `supabase/email-templates/manifest.json` + `TEMPLATE_MANIFEST` in [`_shared/email.ts`](../../supabase/functions/_shared/email.ts) expose the typed surface. HTML-escape is applied to every `{{var}}` interpolation so a hostile `group_name` cannot paint HTML into the email body (same posture as L03-17 decimal parser).

---

## 2. Architecture

```
┌──────────────────────┐    enqueue (idempotent)    ┌──────────────────┐
│ Caller (route /      │ ─────────────────────────► │ fn_enqueue_email │
│ Edge Function / cron)│                            └──────────────────┘
│                      │                                     │
│                      │                                     ▼
│                      │                         ┌────────────────────┐
│                      │                         │ public.email_outbox│
│                      │                         │  (RLS + FORCE RLS) │
│                      │                         └────────────────────┘
│                      │                                     ▲
│                      │   dispatch via provider             │
│                      │ ────────────────────────►  sendEmail()
│                      │                                │
│                      │   POST resend / inbucket / null │
│                      │                                ▼
│                      │                       ┌────────────────────┐
│                      │                       │ fn_mark_email_sent │
│                      │                       │ fn_mark_email_failed│
│                      │                       └────────────────────┘
└──────────────────────┘
```

Callers are **not** expected to call `sendEmail()` directly. The canonical path is **POST `/functions/v1/send-email`** (service-role only), which does the enqueue → dispatch → mark loop atomically. Hotpath callers that already hold a service-role client may inline the 3 RPCs if the overhead of an HTTP hop is measurable, but the happy path is "`fetch(send-email, { body })` and read the result".

### 2.1 Tables + helpers shipped by `20260421360000_l15_04_email_outbox.sql`

| Object | Kind | Purpose |
|---|---|---|
| `public.email_outbox` | table | canonical queue; 1 row / lifecycle; RLS+FORCE; service_role only |
| `email_outbox_idempotency_key_uniq` | unique index | dedup fence — same key → same row |
| `email_outbox_status_created_at_idx` | btree | scan pending or failed rows by age |
| `email_outbox_recipient_user_idx` | partial btree | "all emails sent to user X" |
| `public.fn_enqueue_email(...)` | SECURITY DEFINER | INSERT ... ON CONFLICT DO NOTHING; returns row id |
| `public.fn_mark_email_sent(id, provider, provider_message_id)` | SECURITY DEFINER | idempotent success transition; raises on `failed/suppressed → sent` |
| `public.fn_mark_email_failed(id, error, terminal)` | SECURITY DEFINER | idempotent failure transition; non-terminal keeps `pending`, bumps `attempts`; raises on `sent/suppressed → failed` |
| `public.fn_email_outbox_assert_shape()` | SECURITY DEFINER | CI helper — raises P0010 if the shape drifts |

### 2.2 Code surfaces shipped alongside

| File | Purpose |
|---|---|
| [`supabase/functions/_shared/email.ts`](../../supabase/functions/_shared/email.ts) | Provider abstraction + template registry + `sendEmail()` entrypoint |
| [`supabase/functions/_shared/email.test.ts`](../../supabase/functions/_shared/email.test.ts) | 27 Deno unit tests (escape, render, validate, providers, dispatcher) |
| [`supabase/functions/send-email/index.ts`](../../supabase/functions/send-email/index.ts) | Service-role gated HTTP surface |
| [`supabase/email-templates/manifest.json`](../../supabase/email-templates/manifest.json) | Canonical template registry — matches the `TEMPLATE_MANIFEST` const |
| [`supabase/email-templates/*.html`](../../supabase/email-templates/) | Template bodies (4 shipped: `coaching_group_invite`, `championship_invite`, `weekly_training_summary`, `payment_confirmation`) |
| [`tools/audit/check-email-platform.ts`](../../tools/audit/check-email-platform.ts) | CI guard (`npm run audit:email-platform`) |
| [`tools/test_l15_04_email_outbox.ts`](../../tools/test_l15_04_email_outbox.ts) | 18 integration tests (docker-exec psql) |

---

## 3. How to add a new template

1. **Create the HTML body** at `supabase/email-templates/<key>.html`. Start from a copy of `payment_confirmation.html` to keep the wrapper / footer consistent with design tokens (#0f766e / #6366f1 / #1a1a2e per template; all responsive single-column 600px max width).
2. **Register in the manifest** — edit `supabase/email-templates/manifest.json`:
   ```jsonc
   "streak_break_alert": {
     "subject": "Atleta {{athlete_name}} quebrou a sequência",
     "file": "streak_break_alert.html",
     "required_vars": ["athlete_name", "streak_days", "dashboard_link"],
     "description": "Coach alert when athlete breaks a training streak.",
     "from_name": "OmniRunner",
     "category": "transactional"
   }
   ```
3. **Mirror in `TEMPLATE_MANIFEST`** in `supabase/functions/_shared/email.ts` — add the key to the `EmailTemplateKey` union, add the identical entry to the `Object.freeze({...})` map. **CI enforces this parity** — `check-email-platform.ts` fails if a manifest key is not referenced in `_shared/email.ts`.
4. **Write a test** in `supabase/functions/_shared/email.test.ts` asserting `assertRequiredVars` happy path + render with a hostile value to verify HTML-escape.
5. **Deploy order**: (a) template files commit, (b) `_shared/email.ts` update, (c) code caller that invokes the new template_key. You cannot send an email for a template that isn't yet in the manifest — `send-email` returns `422 UNKNOWN_TEMPLATE`.

---

## 4. Operational playbooks

### 4.1 Provider outage (Resend 5xx storm)

**Signal:** `email_outbox` accumulates rows with `status='pending'` + `attempts >= 1` + `last_error LIKE 'resend HTTP 5__%'`. Sentry shows a spike of `send-email` function errors with `PROVIDER_FAILED`.

```sql
-- How backed up are we right now?
SELECT status, COUNT(*),
       percentile_cont(0.5) WITHIN GROUP (ORDER BY attempts) AS median_attempts,
       MAX(attempts) AS max_attempts
  FROM public.email_outbox
 WHERE created_at > now() - interval '1 hour'
 GROUP BY status;

-- Top 20 stuck rows
SELECT id, template_key, recipient_email, attempts,
       LEFT(last_error, 100) AS last_error, created_at
  FROM public.email_outbox
 WHERE status = 'pending' AND attempts >= 2
 ORDER BY created_at DESC
 LIMIT 20;
```

**Actions** (in priority order):

1. **Confirm at the provider status page** — `https://resend-status.com` (Resend) or dashboard. If they're declaring incident, **do not** deploy fallback; the hot-loop cost of marking non-terminal attempts bumps `attempts` but the outbox row persists and retries on the next manual or scheduled replay.
2. **Manual replay** (when provider recovers) — see §4.4.
3. **Emergency failover to Inbucket** — only if the outage is > 2h AND the email has business deadline (invoice, password reset). Set `EMAIL_PROVIDER=inbucket` in the edge function secrets, re-run send-email; each sent row persists `provider='inbucket'` so later Ops review can see which batch went where. **Never** leave Inbucket in prod — it's in-memory and the emails are not actually delivered to recipients; it's only safe as a "record delivery intent + ops will manually resend after fix".

### 4.2 Template doesn't render / variables show as `{{var}}`

**Signal:** Support receives a screenshot with literal `{{amount}}` in the email body.

**Root cause** is almost always a missing entry in `required_vars` or a caller that forgot a var.

```sql
-- Which rows shipped with this template in the last 24h?
SELECT id, recipient_email, template_vars, sent_at, provider_message_id
  FROM public.email_outbox
 WHERE template_key = '<key>'
   AND status = 'sent'
   AND sent_at > now() - interval '24 hours'
 ORDER BY sent_at DESC
 LIMIT 50;
```

Check the `template_vars` JSON — if the key referenced by `{{amount}}` is absent, the caller is the bug, not the template. Fix the caller; there's no retroactive re-render path (we do not store the rendered HTML to keep the outbox footprint low). The affected users need a manual apology email via `send-email` with a dedicated `apology_<reason>` template.

If `required_vars` was the miss: `assertRequiredVars` would have rejected the enqueue BEFORE dispatch with reason=`missing_vars`. That means the manifest drifted from the template body — add the missing key to `required_vars`, ship a migration-like PR with a test.

### 4.3 Spike of `status='failed'` rows

**Signal:** `check-email-platform` is green but portal dashboards show a sudden uptick in `failed` rows.

```sql
-- Top 10 failure reasons
SELECT LEFT(last_error, 80) AS reason, COUNT(*)
  FROM public.email_outbox
 WHERE status = 'failed'
   AND failed_at > now() - interval '24 hours'
 GROUP BY 1
 ORDER BY 2 DESC
 LIMIT 10;
```

Common patterns:

- `provider_4xx` with `"email_not_verified"` → the **sending domain** was not verified in Resend. Fix the DNS SPF / DKIM entries at the registrar; this is a configuration issue, not a code one.
- `provider_4xx` with `"recipient bounced"` / `"invalid address"` → user typed a bad address at signup. No retry — mark bounced address in `profiles.email_bounced_at` (follow-up L15-05).
- `provider_5xx` alternating with `provider_timeout` → network / DNS / upstream saturation. Wait.
- `missing_vars` / `unknown_template` → code bug in the caller, NOT a provider issue. Fix the caller.

### 4.4 Replay failed batch after provider recovery

```sql
-- Reset non-terminal failures as pending so the sender picks them up.
-- ONLY run this after confirming the failure was provider-side (not bad address).
-- Caveat: fn_mark_email_failed(terminal=false) already keeps status='pending'.
-- So this only applies to batches that were marked terminal in error.
-- Coordinate with ops before running.
UPDATE public.email_outbox
   SET status = 'pending',
       updated_at = now(),
       last_error = COALESCE(last_error || ' [replay_' || to_char(now(), 'YYYYMMDD"T"HH24MISS') || ']', NULL)
 WHERE status = 'failed'
   AND failed_at > now() - interval '6 hours'
   AND last_error ILIKE '%resend HTTP 5%';
```

Then run the cron-scheduled drain (when it lands in L15-05) or manually: iterate over pending rows and POST to `/functions/v1/send-email` with the original `idempotency_key` — enqueue is idempotent, dispatch picks up `pending` and reruns.

### 4.5 GC retention (cron follow-up)

The outbox grows monotonically. A GC cron (planned for L15-05) will prune rows older than 90 days where `status IN ('sent','failed','suppressed')`. Until that ships, run this manually monthly:

```sql
DELETE FROM public.email_outbox
 WHERE status IN ('sent','failed','suppressed')
   AND updated_at < now() - interval '90 days'
   AND created_at < now() - interval '90 days';
```

⚠ **Do NOT** prune rows where `template_key = 'payment_confirmation'` without first mirroring the row into the fiscal receipts projection (L02-09) — LGPD and tax obligations require a 5-year retention on financial documents.

### 4.6 CI guard failed after deploy

```
$ npm run audit:email-platform
  [FAIL] db: fn_email_outbox_assert_shape raised: L15-04: email_outbox shape missing: table:email_outbox(rls_forced) | ...
```

Two flavours:

- `[FAIL] db: ...` — DB is reachable but the shape drifted (someone dropped a CHECK, migrated without re-applying, etc). Re-apply the migration; never hand-edit the tables.
- `[FAIL] shared: ...` — `_shared/email.ts` lost an export. Likely a refactor-gone-wrong; restore the removed export or update the guard (but require a reviewer to sign off on the latter).
- `[FAIL] providers: ...` — Someone wired `fetch('https://api.resend.com/emails')` directly in a route/edge-function. **Reject the PR** unless the commit message explicitly says `L15-04 bypass:` with a justification. The happy path is always `sendEmail()`.

---

## 5. Security posture

- **Service-role only.** The `/send-email` endpoint rejects any caller without the service-role bearer (status 403). The DB helpers have `REVOKE ALL FROM PUBLIC, anon, authenticated` + explicit `GRANT EXECUTE TO service_role`. Enforced by `check-email-platform.ts` test (7).
- **HTML escape by default.** Every `{{var}}` in a template body is HTML-escaped via `escapeHtml` (covers `& < > " ' /`). Unit test `sendEmail — HTML escapes hostile values` asserts this on `<img src=x onerror=alert(1)>`.
- **Subject line NOT escaped.** Email subjects are plain text, not HTML — running escape on them would emit literal `&amp;`. The subject is still safe because it's rendered server-side and sent to the provider's JSON body; there's no HTML boundary.
- **Idempotency fence.** `idempotency_key` is UNIQUE + CHECK(length BETWEEN 8 AND 256). Callers SHOULD derive this from a deterministic key like `withdrawal_id`, `purchase_id`, or `invite_id` to make dedup automatic across retries. Never use a random string on the hot path — that defeats the fence.
- **Outbound network is opt-in.** Default `EMAIL_PROVIDER` is `null`. A production deployment that forgets to set `EMAIL_PROVIDER=resend` will still pass CI + run smoke — but send zero real email. Pair with the `provider_message_id LIKE 'null-%'` check in a weekly ops sweep to catch silent mis-config.

---

## 6. Detection signals

| Signal | Source | Action |
|---|---|---|
| `check-email-platform` red in CI | GitHub Actions / `npm run audit:email-platform` | §4.6 |
| `fn_email_outbox_assert_shape` raises P0010 | DB monitor | redeploy migration |
| `email_outbox.status='pending' AND attempts >= 3` > 50 rows | DB alert | §4.1 |
| `provider_message_id LIKE 'null-%'` in prod for 24h straight | weekly ops sweep | mis-config of `EMAIL_PROVIDER` |
| Spike of `template_vars` keys shipped empty | ad-hoc SELECT | caller bug — fix upstream |
| Resend bounce rate > 5% | Resend dashboard | §4.3 |

---

## 7. Rollback

Defensive refactor: the DB objects are aditivos, so rollback is a simple migration `DROP TABLE public.email_outbox CASCADE; DROP FUNCTION ...`. **Do not** rollback in prod without first draining every pending row — the alternative is a fresh outage where every caller sees `ENQUEUE_FAILED` and nothing downstream captures the intent.

To pause the provider only (not the DB): set `EMAIL_PROVIDER=null` — `sendEmail()` keeps filling the outbox with `status='sent'` + `provider='null'` + fabricated ids, but no outbound HTTP happens. Useful during incident-response cooldown windows.

---

## 8. Cross-refs

- **L10-09** — when we turn on `enable_confirmations = true` for sign-in challenge emails (credential stuffing defence), they go through the same outbox; the `login-pre-check` edge function will enqueue a `sign_in_verification` template. The anti-credential-stuffing counter is independent; it's the throttle. The email itself is just another enqueue.
- **L12-09** — `notification_log` and `email_outbox` are siblings: same "at-most-once delivery per logical event" posture, different transports (push vs email). A single alert event can trigger both (`fn_try_claim_notification('low_credits_alert', ctx_id)` AND `fn_enqueue_email(..., 'low_credits_alert', ..., ctx_id)`). The `ctx_id` is the shared key; the idempotency_key for email can be `low_credits_alert:<user_id>:<day>`.
- **L18-04** — `idempotency_keys` table is for request-level idempotency in financial RPCs. It is NOT the fence for email; email has its own per-row fence because emails come from many call-paths that don't always hold a `request_id`. Do not reuse the tables across domains.
- **L04-07** — `template_vars` MUST NOT leak PII in plaintext through the outbox for L04-07 redaction scope (no CPF, no full name paired with medical data, no health data). If a template needs PII, mark it with `category='pii'` in the manifest (follow-up L15-06) and restrict the outbox retention for that key.
- **L03-17** — money amounts in templates (`{{amount}}`) must already be formatted by the caller via `formatAmountBRL` / `formatCentsAsBRL` — the template body does NOT parse or convert amounts.
