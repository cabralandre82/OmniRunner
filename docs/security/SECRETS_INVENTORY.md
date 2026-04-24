# Secrets inventory (L10-11)

> **Status:** ratified · **Owner:** Security + Platform · **Cadence:** quarterly review · **Last updated:** 2026-04-21
>
> **NEVER commit secret values to this file.** Only secret
> *names*, *locations*, *owners* and *rotation cadence* are
> allowed here. Anyone who pastes a real secret here is paged.

## Reading guide

* **Name** — the variable / file / record name as it appears in
  the runtime (`STRIPE_SECRET_KEY`, etc).
* **Vendor** — who issued the secret.
* **Location** — where the secret is stored at rest. Multiple
  locations means we have copies in sync (intentional duplication).
* **Owner** — the team that owns rotation + revocation (NOT the
  team that uses it day-to-day).
* **Rotation** — how often we rotate. Last rotation date is
  tracked in 1Password, not here.
* **Blast radius** — what breaks if this leaks AND what breaks
  if we rotate without a heads-up.

## Inventory

### Payments

| Name                          | Vendor      | Location                                    | Owner    | Rotation | Blast radius                                                |
|-------------------------------|-------------|---------------------------------------------|----------|----------|--------------------------------------------------------------|
| `STRIPE_SECRET_KEY`           | Stripe      | Vercel env (`portal/prod`) · 1Password       | Finance  | 90 days  | Charges + payouts, 1-tx-block on rotate                      |
| `STRIPE_WEBHOOK_SECRET`       | Stripe      | Vercel env · 1Password                       | Finance  | 90 days  | Webhook HMAC validation; rotation requires Stripe dashboard  |
| `STRIPE_PUBLIC_KEY`           | Stripe      | Vercel env (NEXT_PUBLIC) · public           | Finance  | 90 days  | Public; rotated alongside secret key for hygiene             |
| `MERCADOPAGO_ACCESS_TOKEN`    | MercadoPago | Vercel env · 1Password                       | Finance  | 90 days  | PIX + boleto; rotation requires MP support ticket            |
| `MERCADOPAGO_WEBHOOK_SECRET`  | MercadoPago | Vercel env · 1Password                       | Finance  | 90 days  | Webhook HMAC validation                                      |
| `ASAAS_ACCESS_TOKEN`          | Asaas       | Vercel env · 1Password                       | Finance  | 90 days  | PIX + cartão fallback; quick rotate via Asaas dashboard      |
| `ASAAS_WEBHOOK_SECRET`        | Asaas       | Vercel env · 1Password                       | Finance  | 90 days  | Webhook HMAC validation                                      |

### Backend infra

| Name                          | Vendor      | Location                                    | Owner    | Rotation | Blast radius                                                |
|-------------------------------|-------------|---------------------------------------------|----------|----------|--------------------------------------------------------------|
| `SUPABASE_SERVICE_ROLE_KEY`   | Supabase    | Vercel env · GitHub Actions secret · 1Pass  | Platform | 30 days  | Full DB; rotation invalidates ALL service tokens at once     |
| `SUPABASE_ANON_KEY`           | Supabase    | Vercel env (NEXT_PUBLIC) · public           | Platform | annual   | RLS-enforced; safe in client                                 |
| `SUPABASE_DB_PASSWORD`        | Supabase    | 1Password (DBA only)                         | Platform | 30 days  | psql / pgcli access; rotated via Supabase dashboard          |
| `SUPABASE_JWT_SECRET`         | Supabase    | Vercel env (read-only mirror) · 1Password    | Platform | annual   | Edge Function JWT validation; rotating expires all sessions  |
| `UPSTASH_REDIS_REST_URL`      | Upstash     | Vercel env · 1Password                       | Platform | annual   | Rate-limit + cache; rotation forces fail-closed mode         |
| `UPSTASH_REDIS_REST_TOKEN`    | Upstash     | Vercel env · 1Password                       | Platform | 90 days  | Same as above                                                |

### Observability

| Name                          | Vendor      | Location                                    | Owner    | Rotation | Blast radius                                                |
|-------------------------------|-------------|---------------------------------------------|----------|----------|--------------------------------------------------------------|
| `SENTRY_AUTH_TOKEN`           | Sentry      | GitHub Actions secret · 1Password           | Platform | 90 days  | Source-map upload; rotation only blocks deploys              |
| `SENTRY_DSN`                  | Sentry      | Vercel env (NEXT_PUBLIC) · public           | Platform | annual   | Public; safe in client/mobile                                |
| `BETTERSTACK_HEARTBEAT_URL`   | Better Uptime | Vercel env · 1Password                     | Platform | annual   | Health-check endpoint for cron jobs                          |

### Integrations

| Name                          | Vendor      | Location                                    | Owner    | Rotation | Blast radius                                                |
|-------------------------------|-------------|---------------------------------------------|----------|----------|--------------------------------------------------------------|
| `STRAVA_CLIENT_SECRET`        | Strava      | Supabase Vault · 1Password                   | Integrations | 180 days | OAuth re-link on rotate; user-visible disconnect          |
| `STRAVA_VERIFY_TOKEN`         | Strava      | Supabase Vault · 1Password                   | Integrations | 180 days | Push subscription verification                            |
| `TRAININGPEAKS_CLIENT_SECRET` | TrainingPeaks | Supabase Vault · 1Password                 | Integrations | 180 days | OAuth re-link on rotate                                   |
| `FIREBASE_SERVICE_ACCOUNT`    | Firebase    | Supabase Vault (FCM signer) · 1Password      | Mobile   | 180 days | FCM push delivery; rotation requires APNs/Play update      |
| `MAPBOX_ACCESS_TOKEN`         | Mapbox      | Vercel env (NEXT_PUBLIC) + 1Password         | Mobile   | annual   | Map tiles; rate-limited on per-token basis                  |
| `RESEND_API_KEY`              | Resend      | Vercel env · 1Password                       | Platform | 90 days  | Transactional email; fallback is Postmark                   |
| `POSTMARK_API_TOKEN`          | Postmark    | Vercel env (fallback) · 1Password            | Platform | 90 days  | Transactional email fallback                                |

### CI / supply chain

| Name                          | Vendor      | Location                                    | Owner    | Rotation | Blast radius                                                |
|-------------------------------|-------------|---------------------------------------------|----------|----------|--------------------------------------------------------------|
| `GITHUB_TOKEN`                | GitHub      | Workflow runtime                            | Platform | per-job  | Scoped per workflow; ephemeral                              |
| `VERCEL_TOKEN`                | Vercel      | GitHub Actions secret · 1Password            | Platform | 180 days | Manual deploys + log access                                |
| `GITHUB_PAT_RELEASE`          | GitHub      | GitHub Actions secret · 1Password            | Platform | 90 days  | Tag pushes for release; org admin                          |
| `EXPO_TOKEN`                  | Expo        | GitHub Actions secret · 1Password            | Mobile   | 180 days | EAS Build / Submit; org admin                              |

### Mobile signing

| Name                          | Vendor      | Location                                    | Owner    | Rotation | Blast radius                                                |
|-------------------------------|-------------|---------------------------------------------|----------|----------|--------------------------------------------------------------|
| `ANDROID_UPLOAD_KEYSTORE`     | self        | EAS Secrets · 1Password (encrypted backup)   | Mobile   | NEVER    | Loss = lose Play Store account; backups are non-negotiable  |
| `ANDROID_UPLOAD_KEYSTORE_PASSWORD` | self   | EAS Secrets · 1Password                       | Mobile   | NEVER    | See above                                                  |
| `IOS_DISTRIBUTION_CERT`       | Apple       | EAS Secrets · 1Password                       | Mobile   | annual   | App Store distribution; rotation via Apple Developer       |
| `IOS_PROVISIONING_PROFILE`    | Apple       | EAS Secrets · 1Password                       | Mobile   | annual   | Bundled per-build                                          |

## Rotation runbook reference

For the actual rotate-and-deploy steps, see
[`docs/runbooks/SECRET_ROTATION_RUNBOOK.md`](../runbooks/SECRET_ROTATION_RUNBOOK.md).

## Discovery → onboarding

When a new vendor is integrated, the PR introducing the vendor
MUST update this inventory in the same commit. The
`audit:secret-rotation` CI guard fails when a new
`process.env.<NEW_NAME>` is added but this file is not updated.

## Cross-references

* `docs/runbooks/SECRET_ROTATION_RUNBOOK.md` — quarterly
  rotation procedures (L11-09)
* `docs/audit/findings/L11-09-rotacao-de-segredos-sem-runbook.md`
* `docs/audit/findings/L09-11-segredos-via-supabase-vault.md`
* `tools/audit/check-secret-rotation.ts` — CI guard for
  rotation policy
