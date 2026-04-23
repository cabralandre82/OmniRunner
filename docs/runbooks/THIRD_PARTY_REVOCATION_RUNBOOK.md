# Third-party OAuth revocation runbook — L04-09

> Closes [`L04-09`](../audit/findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md)
> at the **database contract** level. The HTTP worker that talks to
> Strava / TrainingPeaks is a follow-up
> (`L04-09-strava-worker`, `L04-09-tp-worker`) — contract below is
> the API it must satisfy.
>
> **Migration:** `supabase/migrations/20260421420000_l04_09_third_party_revocation.sql`
> **Guard CI:** `npm run audit:third-party-revocation`

---

## 1. Why this exists

When a user erases their account (LGPD Art. 18 VI) or disconnects
a third-party integration, **we must** notify the provider to
invalidate the OAuth token. If we don't:

- Strava keeps syncing new activities via our webhook even after
  the user "left" — LGPD Art. 18 VIII violation (communication to
  third parties).
- The user may not even know the token is still valid, giving them
  no way to revoke it themselves without contacting Strava support.
- In a worst-case, an attacker who compromises our backup could
  re-use the still-valid token to pull fresh data months later.

The migration ships the **queue + audit primitive** so that a
revocation request is recorded the moment a token disappears. The
actual HTTPS call is executed asynchronously by a worker.

## 2. Contract

### 2.1 Entry points

- `public.fn_request_third_party_revocation(user_id, provider, reason, payload_snapshot)`
  → returns `request_id uuid`. Call this from any orchestration
  (e.g., account-deletion API route) when a token-bearing
  integration is removed.
- Trigger `trg_strava_connection_revoke` on `public.strava_connections`
  DELETE enqueues automatically. A manual call is therefore only
  needed for cases where tokens live outside `strava_connections`
  (e.g., TrainingPeaks, future providers).

### 2.2 State machine (append-only, per `request_id`)

```
  requested ─┬→ completed                   ← terminal (OK)
             ├→ failed ──┐
             │           └→ requested (retry, same id)
             ├→ skipped_missing_token       ← terminal (user already
             │                                disconnected at provider)
             ├→ skipped_provider_error_4xx  ← terminal (provider said
             │                                token already invalid)
             └→ abandoned                   ← terminal (retry budget
                                              exhausted — manual review)
```

There is no UPDATE — every transition is a new row in
`public.third_party_revocations` linked by `request_id`. The
`fn_complete_third_party_revocation(request_id, outcome, http_status, error_message)`
helper inserts the new state row and auto-bumps `retry_count` for
`failed` outcomes.

### 2.3 Worker loop (pseudocode)

```ts
// Edge Function / Next.js cron, runs every 5 min.
const { data: due } = await admin.rpc("fn_third_party_revocations_due", {
  p_provider: "strava",
  p_limit: 100,
});

for (const row of due ?? []) {
  // 1. Load the token IF it still exists. If not, mark skipped.
  const { data: conn } = await admin
    .from("strava_connections")
    .select("access_token")
    .eq("user_id", row.user_id)
    .maybeSingle();

  if (!conn) {
    await admin.rpc("fn_complete_third_party_revocation", {
      p_request_id: row.request_id,
      p_outcome: "skipped_missing_token",
    });
    continue;
  }

  // 2. Back-off before retry (exponential, capped at 24h).
  const backoffMs = Math.min(
    (2 ** Math.min(row.retry_count, 14)) * 1000,
    24 * 60 * 60 * 1000,
  );
  if (Date.now() - new Date(row.requested_at).getTime() < backoffMs) continue;

  // 3. Call Strava deauthorize.
  const res = await fetch("https://www.strava.com/oauth/deauthorize", {
    method: "POST",
    headers: { Authorization: `Bearer ${conn.access_token}` },
  });

  if (res.ok) {
    await admin.rpc("fn_complete_third_party_revocation", {
      p_request_id: row.request_id,
      p_outcome: "completed",
      p_http_status: res.status,
    });
  } else if (res.status === 401 || res.status === 403) {
    await admin.rpc("fn_complete_third_party_revocation", {
      p_request_id: row.request_id,
      p_outcome: "skipped_provider_error_4xx",
      p_http_status: res.status,
    });
  } else if (row.retry_count >= 15) {
    await admin.rpc("fn_complete_third_party_revocation", {
      p_request_id: row.request_id,
      p_outcome: "abandoned",
      p_http_status: res.status,
      p_error_message: await res.text(),
    });
  } else {
    await admin.rpc("fn_complete_third_party_revocation", {
      p_request_id: row.request_id,
      p_outcome: "failed",
      p_http_status: res.status,
      p_error_message: await res.text(),
    });
  }
}
```

### 2.4 Retry budget

- Max 20 retries (`retry_count` CHECK) before the row must be
  transitioned to `abandoned`. The worker is expected to enforce
  this via the pseudocode above.
- The 20-retry ceiling with exponential back-off gives a final
  attempt roughly 16 million seconds (~185 days) after the first
  request — well beyond the LGPD worst-case window declared in
  `BACKUP_POLICY.md`. In practice, any provider that rejects our
  DEAUTHORIZE for 20 attempts is either dead or has already
  invalidated the token — either way the end-state from the
  user's LGPD perspective is acceptable.

## 3. Playbooks

### 3.1 "Worker never runs" — revocations stack up

Symptom: `select count(*) from fn_third_party_revocations_due('strava', 10000);`
grows unbounded.

Response:
1. Check Edge Function logs (`supabase functions logs third-party-revoker`).
2. Check that the `STRAVA_CLIENT_ID` / `STRAVA_CLIENT_SECRET` secrets
   are set (the follow-up worker requires them to refresh expired
   access_tokens before calling DEAUTHORIZE; stale access_tokens
   Strava will reject with 401 which we classify as `skipped_provider_error_4xx`).
3. If the worker is down more than 24h, notify DPO — the
   revocation SLA promised in privacy policy is 72h.

### 3.2 Provider rate-limited us

Symptom: many rows transitioning `requested` → `failed` with
`http_status = 429`.

Response:
1. Lower worker `p_limit` from 100 → 20.
2. Widen back-off (extra 10× multiplier) until provider is
   healthy.
3. Strava limits are published at
   <https://developers.strava.com/docs/rate-limits/>. Our
   deauthorize calls share the same rate-limit bucket as webhook
   subscription management.

### 3.3 Manual request (support ticket)

A user emailed `dpo@omnirunner.com` asking us to revoke their
Strava token without deleting the account:

```sql
SELECT public.fn_request_third_party_revocation(
  '<user_uuid>', 'strava', 'dpo_ticket:T-12345', NULL
);
```

Then reply to the user with the `request_id` for traceability.

### 3.4 Undo — user reconnected before the worker ran

The request is already enqueued. The right action is **not** to
delete the row (can't — append-only). Instead, call:

```sql
SELECT public.fn_complete_third_party_revocation(
  '<request_id>', 'abandoned', NULL,
  'user reconnected before revocation executed'
);
```

and log the justification in the DPO decision log.

## 4. What the CI guard enforces

`tools/audit/check-third-party-revocation.ts`
(`npm run audit:third-party-revocation`):

- Migration file exists with the expected name.
- Table `third_party_revocations` declared with required columns
  and CHECK constraints on `provider` + `event` + `retry_count`.
- Auto-enqueue trigger on `strava_connections` DELETE.
- Functions `fn_request_third_party_revocation`,
  `fn_third_party_revocations_due`,
  `fn_complete_third_party_revocation` declared `SECURITY DEFINER`
  with explicit `search_path` and `service_role` grants (no
  `authenticated` / `anon` leak).
- Register-with-L10-08 installer call present.
- Self-test block exercises enqueue → due → completed → DELETE-blocked.
- Runbook cross-links the migration, the CI guard, and the finding.

## 5. Cross-links

- [`L04-09 finding`](../audit/findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md)
- [`Migration`](../../supabase/migrations/20260421420000_l04_09_third_party_revocation.sql)
- [`L10-08 runbook`](./AUDIT_LOGS_RETENTION_RUNBOOK.md)
- [`BACKUP_POLICY.md`](../compliance/BACKUP_POLICY.md)
- [`STRAVA_OAUTH_CSRF_RUNBOOK.md`](./STRAVA_OAUTH_CSRF_RUNBOOK.md)
