# LGPD Data Portability — `export-my-data` Runbook

**Status:** Specified (2026-04-21), implementation in Wave 3.
**Owner:** legal + platform
**Regulatory ref:** LGPD Art. 18, V ("portabilidade dos dados a
outro fornecedor de serviço").
**Related:** L04-15, L04-01 (delete-my-data, fail-safe RPC),
L04-04 (health data hardening), `docs/runbooks/DPO_CHANNEL.md`
(L04-11), `docs/legal/CONSENT_REGISTRY.md` (L04-03).

## Question being answered

> "LGPD Art. 18 V grants the data subject the right to receive
> their data in a structured, common, machine-readable format
> for transfer to another provider. What endpoint do they hit,
> what's in the export, and how long does the link live?"

## Decision

**Self-service from the user's account screen**, async fan-out
to a Supabase Edge Function, signed Storage URL emailed to the
authenticated user.

```
  Account screen → POST /api/account/export
                          │
                          ▼ (enqueue, 202)
                  fn_enqueue_data_export(uid)
                          │
                          ▼ (cron / pg_net trigger)
                  Edge Function: export-my-data
                          │
                          ▼
                  storage/exports/{uid}/{ts}.zip (signed, 24h)
                          │
                          ▼
                  Resend email with one-click download link
                          │
                          ▼
                  audit_logs(event_domain='lgpd',
                             action='data_export.delivered')
```

## What's in the export

A single `.zip` containing one folder per data domain. All
files UTF-8, no system metadata. Manifest at the root.

```
omni-runner-export-{uid}-{YYYY-MM-DD}.zip
├── README.txt                # plain-text guide for the user
├── manifest.json             # checksum + row counts per file
├── profile/
│   ├── profile.json          # public profile fields
│   └── consents.json         # consent_grants + versions
├── runs/
│   ├── sessions.csv          # all sessions, denormalised
│   └── trajectories/         # GPX files (one per session)
│       └── {session_id}.gpx
├── wallet/
│   ├── wallets.json          # current balances per group
│   ├── coin_ledger.csv       # all credits/debits, scoped to user_id
│   └── withdrawals.csv       # withdrawals + status history
├── coaching/
│   ├── memberships.json      # coaching_members rows
│   └── championships.csv     # championships joined / awards
├── integrations/
│   ├── strava.json           # OAuth bindings (no tokens — those are server-side)
│   └── trainingpeaks.json
└── badges/
    └── badges.csv
```

**Excluded by design** (reasoning in each line):

- Other users' data (e.g. coaches' notes about the athlete) —
  not the subject's data, separate erasure right.
- OAuth provider tokens — secrets, would let the recipient
  hijack the integration.
- `audit_logs` raw — too noisy and contains operational
  metadata (request IDs, IPs) that are not "the user's data"
  in the LGPD sense. We include a `data_export.delivered`
  entry in the manifest so the user knows the export
  happened, but not the full log.
- Health-data raw payloads (`heart_rate_history` etc., per
  L04-04) — included only if the user opts in via the export
  request screen, with a clear warning that the file may
  contain biometric data.

## Endpoint contract

`POST /api/account/export`

- Auth: bearer JWT, no extra scope.
- Rate limit: **1 request per user per 24 h** (`fail_closed`,
  Redis-backed).
- Idempotency: the rate limit IS the idempotency. A second
  POST within 24 h returns `429 RATE_LIMITED` with
  `Retry-After: <seconds-until-next-window>`.
- Body: optional `{ "include_health_raw": boolean }`. Default
  `false`.
- Response: `202 Accepted` with
  `{ "request_id": "...", "estimated_ready_at": "<iso>" }`.

Server side:

1. `fn_enqueue_data_export(uid, include_health_raw)` writes a
   row to `data_export_requests` (RLS forced, owner can SELECT
   their own).
2. The hourly `data-export-cron` picks up `pending` rows and
   invokes the `export-my-data` Edge Function with retries
   (L06-05 wrapper).
3. The Edge Function runs the dump, writes the ZIP to
   `storage/exports/{uid}/{ts}.zip`, generates a 24-h signed
   URL, sends Resend email, marks the row `delivered`.
4. After 24 h the file is hard-deleted by the
   `data-export-gc-daily` cron and the row is moved to a
   `data_export_history` partition for audit (signed URL +
   delivery timestamp retained, ZIP itself gone).

## Operational guardrails

- **Storage cap.** Each export is hard-capped at 500 MB. If
  the user has more data than fits (millions of GPS points),
  the manifest links a paginated set of CSV / GPX files
  instead of forcing a 500 MB single archive.
- **Email delivery.** Uses the existing Resend transactional
  bucket. If the email bounces twice, on-call gets paged via
  the DPO channel (L04-11) and we fall back to in-app
  notification with the signed URL.
- **No cross-tenant escalation.** The Edge Function uses the
  user's JWT (RLS enforced) for all reads. `service_role`
  client is only used to write the ZIP into Storage and to
  set the `delivered` status — never to read user data.
- **Consent registry inclusion.** The export bundles
  `consent_grants` rows + the document hashes from
  `consent_policy_versions` (L09-09), so the user has a
  cryptographic receipt of every contract version they
  accepted.

## Why this is in Wave 3, not now

- The Edge Function is a non-trivial dump (joins 14 tables,
  streams GPX files, builds ZIP) and needs a load test
  against a synthetic "5-year-power-user" account to confirm
  the 500 MB cap.
- Storage signed-URL TTL + GC cron are new infrastructure
  pieces.
- Resend templating + bounce handling for this specific
  template needs legal copy review (the email represents a
  formal LGPD response).
- Row-level cap on `data_export_requests` (1/24h) reuses the
  rate-limit pattern but needs a dedicated table because
  Redis state is not a system-of-record.

Closing this finding now means the **shape of the export is
ratified** and the Wave-3 build has zero design questions.

## See also

- `docs/runbooks/DPO_CHANNEL.md` (L04-11) — manual fallback
  path when self-service fails.
- `supabase/functions/delete-my-data/` (L04-01) — sibling
  endpoint, similar fan-out pattern.
- `docs/runbooks/EDGE_RETRY_WRAPPER_RUNBOOK.md` (L06-05) —
  retry pattern reused here.
