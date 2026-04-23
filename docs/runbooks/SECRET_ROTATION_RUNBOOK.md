# Secret Rotation Runbook

> **Audit ref:** L06-11
> **Owner:** Platform / SRE
> **Cadence:** every 90 days (180 days for `SUPABASE_SERVICE_ROLE_KEY`)
> **Last reviewed:** 2026-04-23

This runbook is the canonical procedure for rotating production
secrets without service downtime. Each section is a self-contained
playbook that can be executed by a single on-call engineer.

---

## 1. Inventory

| Secret | Where it lives | Cadence | Owner | Blast radius |
|---|---|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel + Supabase EF + GH Actions | 180d | Platform | All RLS bypassed if leaked |
| `SUPABASE_ANON_KEY`         | Vercel + mobile app config | rotate only on incident | Platform | Public-by-design; rotate only if abused |
| `STRIPE_WEBHOOK_SECRET`     | Vercel + Stripe Dashboard | 90d | Finance | Forged webhook → fake payments |
| `MP_WEBHOOK_SECRET`         | Vercel + Mercado Pago Dash | 90d | Finance | Same as Stripe |
| `ASAAS_API_KEY`             | Vercel + Asaas Dash | 90d | Finance | Initiate fake transfers |
| `STRAVA_CLIENT_SECRET`      | Vercel + mobile (?) | 365d | Integrations | Hijack OAuth callbacks |
| `TRAININGPEAKS_CLIENT_SECRET` | Vercel | 365d | Integrations | Hijack OAuth callbacks |
| `SENTRY_AUTH_TOKEN`         | Vercel + GH Actions | 365d | SRE | Read all error data |
| `VERCEL_LOG_DRAIN_SECRET`   | Vercel + Axiom | 365d | SRE | Sign log webhooks |
| `JWT_SIGNING_KEY` (Supabase managed) | Supabase only | rotate via Supabase support | Platform | Forge any JWT |

---

## 2. Universal procedure

Every rotation follows the same five-step shape:

1. **Generate** new secret in the provider dashboard.
2. **Add as `*_NEXT`** in Vercel & GH Actions, leaving the old one
   live. Both are now valid simultaneously (where supported).
3. **Deploy** so all running instances see both keys (verifier
   tries `*_NEXT` first then falls back to current).
4. **Promote**: rename `*_NEXT` → primary, demote primary →
   `*_PREV`. Wait one deploy cycle to confirm no fallback errors
   are reported.
5. **Revoke** in the provider dashboard. Remove `*_PREV` from
   Vercel.

For secrets that **do not** support multi-active keys (e.g. some
OAuth client secrets), use a **maintenance window** approach
(§3.4 below).

---

## 3. Per-secret playbooks

### 3.1 SUPABASE_SERVICE_ROLE_KEY (180d)

> **Risk:** if leaked, an attacker bypasses **all** RLS. This is
> THE most sensitive secret in the stack.

1. Open Supabase Dashboard → Project → Settings → API → "Reset
   service_role JWT".
2. Capture the new JWT.
3. In Vercel: add `SUPABASE_SERVICE_ROLE_KEY_NEXT=<new>` env var
   in **Production** scope. Keep current key live.
4. Deploy `chore(secret): rotate service_role to NEXT slot`.
5. Smoke-test 5 critical paths:
   - `POST /api/swap`
   - `POST /api/custody/withdraw`
   - `GET  /api/coaching/[id]/daily-digest`
   - `POST /api/admin/feature-flags/toggle`
   - `npm run e2e:critical`
6. Promote: rename `_NEXT` → primary, primary → `_PREV`.
7. Wait 24h; check Sentry for `auth.invalid_jwt` events.
8. Remove `_PREV` from Vercel.
9. Update `audit_logs.category='secret_rotation'` with
   `rotated_at`, `actor_user_id`, `secret_id='supabase_service_role'`.

### 3.2 STRIPE_WEBHOOK_SECRET / MP_WEBHOOK_SECRET (90d)

> **Risk:** if leaked, attacker can forge webhooks → fake
> payments accepted. Stripe and MP both support **two active
> webhook secrets** during rotation.

1. Provider dashboard → Webhooks → "Roll signing secret".
2. Add `STRIPE_WEBHOOK_SECRET_NEXT=<new>` to Vercel.
3. Deploy. Webhook handler tries `_NEXT` first, falls back to
   primary (see `portal/src/lib/webhooks/verify.ts`).
4. Send test webhook from provider dashboard; confirm 200.
5. Promote primary ← `_NEXT`.
6. Revoke old secret in provider dashboard.

### 3.3 ASAAS_API_KEY (90d)

> **Risk:** if leaked, attacker can initiate transfers from
> custody account.

1. Asaas Dashboard → Integrations → API → Generate new key.
2. **Asaas does NOT support dual-active keys.** Use maintenance
   window (§3.4).
3. Pause webhook processing for 5 minutes via feature flag
   `asaas_webhook_enabled=false`.
4. Update Vercel env `ASAAS_API_KEY=<new>`.
5. Deploy.
6. Re-enable feature flag.
7. Smoke test: query custody balance.
8. Revoke old key in Asaas dashboard.

### 3.4 Maintenance-window template (no dual-active)

For providers that don't support dual keys:

1. Schedule maintenance window via status page banner +
   in-app banner (Tuesday 03:00 BRT, low-traffic).
2. Pause affected feature via flag.
3. Replace secret in Vercel.
4. Deploy.
5. Resume feature.
6. Revoke old secret.

---

## 4. Emergency rotation (suspected leak)

If a secret is suspected leaked:

1. **Immediately** rotate using the procedure above; SLA = 30
   minutes from suspicion to revocation.
2. Open incident ticket; classify as P1 (security).
3. Notify DPO if user data was potentially exposed (LGPD Art. 48
   notification within 48h preliminary).
4. Postmortem within 5 business days.

---

## 5. Cadence enforcement

The CI job `secret-rotation-cadence-monitor` runs daily and:

- Reads `audit_logs` for last `secret_rotation` events.
- For each secret, computes `now() - last_rotation`.
- Opens a P3 issue when `> cadence × 0.9`.
- Opens a P2 issue when `> cadence × 1.0`.

---

## 6. Cross-references

- `.github/workflows/portal.yml` — uses pinned secret env names.
- `portal/src/lib/webhooks/verify.ts` — multi-key webhook
  verification (used during rotation overlap).
- L01-49 — actor_id for audit_logs.
- L10-11 — full inventory of third-party API keys.
- L10-14 — JWT refresh token rotation (related but distinct).

---

## 7. Histórico

| Versão | Data | Mudança |
|---|---|---|
| 1.0 | 2026-04-23 | Documento inicial — fecha L06-11. |
