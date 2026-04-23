# Service-Role Key Rotation Runbook

**Finding:** [L10-03](../audit/findings/L10-03-service-role-key-distribuida-amplamente.md)
**Cadence:** Quarterly (first business day of Jan / Apr / Jul / Oct) + **ad hoc** on any suspected leak.
**Blast radius if skipped:** a single leaked key grants full bypass of every RLS policy on the platform.

## 0. Context

`SUPABASE_SERVICE_ROLE_KEY` is the highest-privilege credential we hold. It is consumed by:

- Supabase Edge Functions (15+) — `createClient(..., SERVICE_ROLE_KEY)`.
- Next.js portal server runtime — `portal/src/lib/supabase/service.ts`, `portal/src/lib/supabase/admin.ts`.
- GitHub Actions (`.github/workflows/*.yml`) — E2E, k6 load, audit-on-main.
- Vercel production + preview environments.

The canonical inventory of every place this key is expected to appear lives in [`docs/security/SERVICE_ROLE_USAGE_INVENTORY.md`](../security/SERVICE_ROLE_USAGE_INVENTORY.md) and is enforced by the `audit:service-role-inventory` CI guard. Any new consumer **must** be added to that inventory before it can ship.

## 1. Environment matrix

| Env                    | Secret name                           | Who can rotate          | Rotation cadence |
| ---------------------- | ------------------------------------- | ----------------------- | ---------------- |
| production             | `SUPABASE_SERVICE_ROLE_KEY`           | `@security` on-call     | quarterly        |
| staging                | `SUPABASE_SERVICE_ROLE_KEY_STAGING`   | `@platform-eng`         | monthly          |
| PR preview             | `SUPABASE_SERVICE_ROLE_KEY_PREVIEW`   | `@platform-eng` + bot   | on every merge   |
| CI (e2e, k6)           | `SUPABASE_SERVICE_ROLE_KEY_CI`        | `@platform-eng`         | monthly          |

**Invariant:** the `production` key is never injected into PR previews, CI, or staging. Each column in the matrix maps to a distinct Supabase project (or at minimum a distinct key rotated on its own schedule).

## 2. Quarterly rotation — prod

**Window:** Monday 09:00–11:00 BRT. Off-hours only if shedding incident load.

### 2.1 Pre-rotation (T-24h)

1. Announce in `#eng-announce`: "service-role key rotation {date} 09:00 BRT, full outage risk ~30s if edge functions fail warm-up".
2. Verify `audit:service-role-inventory` passes on `main`:
   ```bash
   npm run audit:service-role-inventory
   ```
3. Verify `docs/security/SERVICE_ROLE_USAGE_INVENTORY.md` is current (expected file list matches grep).
4. Confirm `@security` on-call has Supabase project-owner access.

### 2.2 Rotation (T-0)

1. In Supabase dashboard → Project Settings → API → **"Reset service role JWT"**. Capture the new key into 1Password → `Service Role — <env> — <YYYY-QQ>`.
2. Update secrets in **this exact order** (fastest propagation first):
   1. Vercel (production scope) via `vercel env add`.
   2. Supabase Edge Function secrets (`supabase secrets set SUPABASE_SERVICE_ROLE_KEY=...`).
   3. GitHub Actions repo secret `SUPABASE_SERVICE_ROLE_KEY` (production scope).
3. Trigger `vercel deploy --prod` (serverless envs only read on cold start).
4. Trigger redeploy of edge functions:
   ```bash
   supabase functions deploy --no-verify-jwt
   ```
   or whichever subset we touched.

### 2.3 Post-rotation verification (T+5min)

Run every script end-to-end:

```bash
npm run smoke:prod
npm run audit:service-role-inventory
```

Specifically verify:

- One Asaas webhook delivers with `HTTP 200`.
- One portal dashboard loads without `401`.
- One scheduled cron (e.g. `settle-challenge`) runs on schedule in the next 10 minutes.

### 2.4 Audit (T+1h)

1. Grep `portal_audit_log` for any row with `action = 'billing_provider.key_access'` between rotation start and T+1h — should be only legitimate edge-function calls.
2. Capture rotation evidence into the quarterly SOC2 evidence bucket:
   ```bash
   ./tools/ops/collect-rotation-evidence.sh service-role $(date +%Y-Q%q)
   ```

### 2.5 Deprecate old key

Remove the previous key from 1Password (move to `Archive` vault, keep for 90 days for forensic purposes) and clear it from any ad-hoc developer shells.

## 3. Ad-hoc rotation (suspected leak)

**Go immediately. Do not wait for the quarterly window.**

1. Page `@security` via PagerDuty.
2. Run the rotation above at high speed; accept the brief deploy gap.
3. Inside the first 15 minutes, run:
   ```sql
   -- Any unusual service-role reads of credential material
   SELECT action, metadata, created_at
   FROM public.portal_audit_log
   WHERE action IN ('billing_provider.key_access', 'billing_provider.key_set')
     AND created_at > now() - interval '7 days'
   ORDER BY created_at DESC
   LIMIT 500;
   ```
4. Invalidate every user session on compromised projects if warranted: `auth.admin.signOutAll()` via edge-function one-shot.
5. File a `L10-XX security-incident-<id>` finding with the incident writeup; link the rotation PR.

## 4. CI enforcement

The `audit:service-role-inventory` guard (`tools/audit/check-service-role-inventory.ts`) does the following on every PR:

1. Greps the repo for `SUPABASE_SERVICE_ROLE_KEY` (and the `_STAGING`/`_PREVIEW`/`_CI` variants).
2. Confirms every hit lives in a file listed in `docs/security/SERVICE_ROLE_USAGE_INVENTORY.md` under the **Expected consumers** section.
3. Fails the build on any new unlisted consumer — forcing explicit security-review when a new place needs the key.
4. Verifies the inventory file itself references this runbook and the L10-03 finding.

## 5. Contacts

- `@security-oncall` (PagerDuty: `security-primary`)
- `@platform-eng` (Slack: `#platform-eng`)
- Incident coord: `#incident-bridge`

## 6. Cross-links

- [L10-03 finding](../audit/findings/L10-03-service-role-key-distribuida-amplamente.md)
- [L06-11 finding — secret rotation](../audit/findings/L06-11-secret-rotation-sem-playbook.md)
- [L09-06 runbook — KMS key GUC](../audit/findings/L09-06-gateway-de-pagamento-asaas-chave-armazenada-em-plaintext.md)
- [Service Role Usage Inventory](../security/SERVICE_ROLE_USAGE_INVENTORY.md)
