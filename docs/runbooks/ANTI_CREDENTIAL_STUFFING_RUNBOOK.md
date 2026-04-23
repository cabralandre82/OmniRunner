# Anti credential stuffing runbook

> Finding: [L10-09](../audit/findings/L10-09-falta-defesa-anti-credential-stuffing-no-mobile-portal.md)
> Migration: [`20260421340000_l10_09_anti_credential_stuffing.sql`](../../supabase/migrations/20260421340000_l10_09_anti_credential_stuffing.sql)
> Scope: DB + Edge Function + Portal + Mobile · Owner: platform-security

## 1. TL;DR

Supabase Auth only rate-limits by IP. A distributed attacker testing
`1000 emails × 1 password` from a botnet never trips the per-IP limit,
because each IP sends a single request.

**Fix** adds a DB-backed, **email-scoped** throttle:

* `public.auth_login_attempts` — one row per (email_hash, window_start).
  Email is never stored raw; only a SHA-256 hex (64 chars). RLS forced,
  service_role only.
* `public.auth_login_throttle_config` — singleton with the operator
  knobs (`fail_threshold_captcha`, `fail_threshold_block`,
  `window_seconds`, `block_seconds`).
* Primitives:
  * `fn_login_throttle_record_failure(email_hash, ip)` — upsert + return
    decision jsonb.
  * `fn_login_throttle_record_success(email_hash)` — reset on 200.
  * `fn_login_throttle_probe(email_hash)` — read-only UI banner source.
  * `fn_login_throttle_cleanup()` — hourly cron housekeeping.
* CI: `npm run audit:anti-credential-stuffing`.

Default policy (tune via the config row):

| Threshold                  | Default | Effect                           |
| -------------------------- | ------- | -------------------------------- |
| `fail_threshold_captcha`   | 3       | UI must render hCaptcha          |
| `fail_threshold_block`     | 10      | Reject with 429 for `block_seconds` |
| `window_seconds`           | 900     | Rolling 15-minute window         |
| `block_seconds`            | 900     | Lockout duration                 |

## 2. Call-site wiring (expected)

Neither the portal nor the mobile client can talk to
`fn_login_throttle_*` directly (service_role only). Wire them through a
small Edge Function:

```
POST /functions/v1/login-pre-check
  body: { email, ip?, outcome?: "success"|"failure", captcha_token? }
```

Flow:

1. Client → `login-pre-check` *before* sending credentials:
   * compute `email_hash = sha256(lower(trim(email)))`
   * call `fn_login_throttle_probe(email_hash)`
   * if `locked=true` → return 429 with `locked_until`
   * if `requires_captcha=true` → demand hCaptcha; return 200 with `require_captcha: true`
   * otherwise → return 200 `require_captcha: false`
2. Client issues `supabase.auth.signInWithPassword({ email, password })`.
3. Client reports the outcome to `login-pre-check`:
   * on failure (Supabase Auth 400/401) → `fn_login_throttle_record_failure`
   * on success (200) → `fn_login_throttle_record_success`

The Edge Function is deliberately out of scope for this migration — the
migration only lays the DB foundation + CI guard. Add it in the next PR
under `supabase/functions/login-pre-check/`.

## 3. Detection and CI

```sql
SELECT public.fn_login_throttle_assert_shape(); -- raises P0010 if any drift
```

CI gate `npm run audit:anti-credential-stuffing` runs the assertion and
fails the pipeline if the migration has been rolled back or tampered
with (missing function, RLS relaxed, anon gained EXECUTE).

Ad-hoc probes:

```sql
-- how many active counters / how many locked accounts right now
SELECT
  count(*)                                   AS counters,
  count(*) FILTER (WHERE locked_until > now()) AS locked_now,
  count(*) FILTER (WHERE captcha_required_at IS NOT NULL) AS captcha_required
FROM public.auth_login_attempts;

-- top 10 most attacked hashes in the last 24 h
SELECT email_hash, sum(attempts) AS total_attempts
FROM public.auth_login_attempts
WHERE last_attempt_at > now() - interval '24 hours'
GROUP BY email_hash
ORDER BY total_attempts DESC
LIMIT 10;
```

## 4. Operational scenarios

### 4.1 Legitimate user locked out

```sql
-- 1. find the offender
SELECT email_hash, attempts, locked_until
FROM public.auth_login_attempts
WHERE email_hash = encode(digest(lower(trim('user@example.com')), 'sha256'), 'hex')
ORDER BY window_start DESC;

-- 2. unlock (record_success resets all counters for the email)
SELECT public.fn_login_throttle_record_success(
  encode(digest(lower(trim('user@example.com')), 'sha256'), 'hex')
);
```

Log the intervention in `portal_audit_log` with
`action='auth.throttle.manual_unlock'`.

### 4.2 Tuning thresholds under attack

```sql
-- tighten captcha threshold to 2 + shorten window to 5 min
UPDATE public.auth_login_throttle_config
SET fail_threshold_captcha = 2,
    window_seconds         = 300,
    updated_at             = now(),
    updated_by             = auth.uid()
WHERE id = 1;
```

Changes take effect **immediately** — subsequent
`fn_login_throttle_record_failure` / `fn_login_throttle_probe` reads
the fresh config. Always return to defaults once the attack subsides
(attackers will normalise under tight thresholds and start hurting
real users).

### 4.3 Periodic cleanup

Schedule:

```sql
SELECT cron.schedule(
  'auth-throttle-cleanup',
  '17 * * * *',                -- hourly at :17
  $$ SELECT public.fn_login_throttle_cleanup(); $$
);
```

Cleanup keeps rows whose window is older than `window_seconds * 4` and
whose lock (if any) has already expired. Without this, the table grows
linearly with the attack surface.

## 5. Privacy notes

* **Never** store raw email. The CHECK on `email_hash` refuses
  anything other than a 64-char lowercase hex string.
* `last_ip` is kept as `inet` and may be omitted by the caller
  (`fn_login_throttle_record_failure(..., NULL)`); useful for
  strict-privacy deployments.
* `auth_login_attempts` is **not** linkable to `auth.users` — it is the
  hash of the attempted email which may not even exist as a user. This
  is a deliberate defence-in-depth choice (we throttle the credential
  *guess*, not the identity).

## 6. Rollback

```sql
BEGIN;
DROP FUNCTION IF EXISTS public.fn_login_throttle_assert_shape();
DROP FUNCTION IF EXISTS public.fn_login_throttle_cleanup();
DROP FUNCTION IF EXISTS public.fn_login_throttle_probe(text);
DROP FUNCTION IF EXISTS public.fn_login_throttle_record_success(text);
DROP FUNCTION IF EXISTS public.fn_login_throttle_record_failure(text,inet);
DROP FUNCTION IF EXISTS public.fn_login_throttle_window_start(integer);
DROP TABLE IF EXISTS public.auth_login_attempts;
DROP TABLE IF EXISTS public.auth_login_throttle_config;
COMMIT;
```

CI will turn red (`fn_login_throttle_assert_shape missing`). Do NOT
rollback unless you are replacing the mechanism with an equivalent
(e.g., a WAF layer).

## 7. Cross-refs

* L10-07 (JWT audience/issuer) — follow-up sibling in Batch E.
* L10-08 (audit_logs append-only) — the success/failure audit trail
  will land there.
* L06-04 (cron health monitor) — schedule `fn_login_throttle_cleanup`
  through the existing monitor.
* L17-06 (CSRF) — the `login-pre-check` Edge Function must enforce the
  existing CSRF contract.
