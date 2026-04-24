# Partner / SaaS Tiering Strategy

**Status:** Ratified (2026-04-21), implementation Wave 3+.
**Owner:** product + platform + sales
**Related:** L16-07 (TrainingPeaks OAuth), L16-09 (SSO),
L16-10 (sandbox tier), L16-03 (partner API — critical, still
pending), L14-09 (per-partner quotas), L09-08 (multi-tenant
plan).

## Question being answered

The audit listed three related findings as separate items but
they all belong to the same problem space — **how do we
package the platform for paying enterprise customers**:

- L16-07: TrainingPeaks OAuth credentials are platform-global
  (all clubs share one app). Enterprise customer would want
  their own.
- L16-09: No SAML / OIDC SSO for enterprise customers with
  Active Directory.
- L16-10: No sandbox environment for partners to test
  integrations before signing.

The right answer is one decision: **a tier model** that
governs all three.

## Tiers

| Tier         | Price (BRL/MAU/mo) | Custody / wallet | Marketplace | API   | Sandbox | OAuth integrations | SSO    |
|--------------|--------------------|------------------|-------------|-------|---------|--------------------|--------|
| **Starter**  | 0.5 (free trial)   | yes              | n/a         | n/a   | shared  | platform-shared    | no     |
| **Pro**      | 2.0                | yes              | yes         | read  | shared  | platform-shared    | no     |
| **Business** | 5.0                | yes              | yes         | r/w   | shared  | platform-shared    | optional |
| **Enterprise** | negotiated       | yes              | yes         | r/w   | dedicated | per-tenant         | yes (SAML/OIDC) |

## L16-07 — Per-tenant OAuth credentials

**Decision:** Enterprise tier gets its own
`integration_credentials` row per provider; sub-Enterprise
tiers share the platform-global credentials (today's
behaviour).

```sql
CREATE TABLE public.integration_credentials (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES coaching_groups(id) ON DELETE CASCADE,
  provider        text NOT NULL CHECK (provider IN ('strava','trainingpeaks','garmin','wahoo')),
  client_id_enc   bytea NOT NULL,                  -- pgcrypto
  client_secret_enc bytea NOT NULL,
  scopes          text[] NOT NULL,
  rotated_at      timestamptz NOT NULL DEFAULT now(),
  rotated_by      uuid NOT NULL REFERENCES profiles(id),
  UNIQUE (group_id, provider)
);

ALTER TABLE public.integration_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_credentials FORCE  ROW LEVEL SECURITY;

CREATE POLICY ic_admin ON public.integration_credentials
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM coaching_members
     WHERE user_id = auth.uid()
       AND group_id = integration_credentials.group_id
       AND role = 'admin_master'
  ));
```

The `trainingpeaks-oauth` Edge Function checks for a per-tenant
row first; falls back to env vars (the platform-global app)
otherwise. Migration is therefore additive — no existing tenant
breaks.

Keys are encrypted at rest with `pgsodium` (`crypto_aead_*`),
keyset rotated quarterly. UI surface
`/platform/group/[id]/integrations` allows the tenant
admin_master to paste their own client_id / client_secret from
the upstream provider's developer portal.

## L16-09 — SSO (SAML / OIDC) for Enterprise

**Decision:** Use Supabase's built-in SSO (paid tier, ~ USD
25/SSO-tenant/month) once we cross 3 Enterprise customers
(otherwise the engineering cost of integrating WorkOS or Keycloak
isn't worth it).

```sql
CREATE TABLE public.sso_providers (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL UNIQUE REFERENCES coaching_groups(id) ON DELETE CASCADE,
  protocol      text NOT NULL CHECK (protocol IN ('saml','oidc')),
  supabase_sso_id text NOT NULL,            -- the ID issued by Supabase
  domain        text NOT NULL,              -- email domain bound to the IdP
  enforced      boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);
```

Login flow:

1. User types email; portal looks up
   `sso_providers WHERE domain = <email-domain>`.
2. If a row exists and `enforced = true`, the password field
   is hidden and the user is redirected through the SAML/OIDC
   loop.
3. If not, the regular email-link / Google OAuth path applies.

Operational rules:

- SCIM provisioning is OUT of scope for v1 (manual user
  creation by admin_master is fine for our customers' typical
  team size of < 50 staff).
- The `enforced` flag exists so a tenant can configure SSO
  without forcing every existing user immediately (graceful
  rollout window).

## L16-10 — Sandbox tier

**Decision:** A separate Supabase project (`omnirunner-sandbox`)
with a public sign-up allowlist + isolated data. Custody/swap
RPCs in sandbox use a **fake-money mode**: `coin_ledger` rows
are tagged `is_sandbox=true`, withdrawal endpoints return 200
without actually moving money, custody.deposit credits a
predictable 1000 OmniCoins regardless of payment.

API key shape: `or_test_<random-32>` for sandbox,
`or_live_<random-32>` for production. The two project URLs
are siblings:

- `api.sandbox.omnirunner.com` → sandbox project.
- `api.omnirunner.com` → production project.

Same code path, different env vars (`OMNI_ENV=sandbox|prod`)
which gates the fake-money mode. Enforcement is server-side
ONLY; the sandbox project is segregated at the Supabase level
so even a leaked sandbox API key cannot reach production data.

Documentation lives at `docs.omnirunner.com/sandbox` (not yet
built — Wave 3 alongside L16-03 partner-API public docs).

### Why "separate Supabase project" not "schema separation"

Schema separation in the same project would be cheaper but:

1. A shared connection pool means a misbehaved sandbox
   integration test could exhaust connections in production.
2. A misconfigured RLS policy could leak across schemas.
3. Backups / restores would be coupled.

Two projects keeps blast radius bounded; the marginal Supabase
cost (~ USD 25/m for the sandbox project on Pro tier) is
acceptable.

## Implementation phasing

| Phase | Scope                                                                                  | When                  |
|-------|----------------------------------------------------------------------------------------|-----------------------|
| 0     | Spec ratified                                                                          | 2026-04-21            |
| 1     | `integration_credentials` table + per-tenant OAuth path in `trainingpeaks-oauth`        | Wave 3                |
| 2     | `sso_providers` table + login flow gate                                                | Triggered by 3rd Enterprise customer signed |
| 3     | Sandbox Supabase project + `OMNI_ENV` gate + `or_test_` keys                           | Concurrent with L16-03 partner-API build |
| 4     | Tier UI in `/platform/billing` + Stripe pricing IDs                                    | Wave 3                |

Closing all three findings in this single spec means any
Enterprise sales conversation has clear technical answers
without waiting for build-time decisions.
