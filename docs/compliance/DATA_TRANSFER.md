# International data transfer policy — Omni Runner

> **Finding:** [`L04-10`](../audit/findings/L04-10-transferencia-internacional-de-dados-supabase-us-sentry-us.md)
> **Owner:** DPO (founder until dedicated role is filled).
> **Review cadence:** annual, or within 30 days of any change to
> provider, region, or LGPD regulatory guidance.
> **Guard CI:** `npm run audit:data-transfer`.

This document describes every cross-border transfer of personal
data Omni Runner performs and the legal basis for each one,
fulfilling LGPD Art. 33 documentation requirements.

---

## 1. Current state (2026-04-21, Sprint 25.0.0)

| Processor   | Purpose                         | Region today     | Data categories transferred | Legal basis |
|-------------|---------------------------------|------------------|-----------------------------|-------------|
| Supabase    | Primary datastore + auth + edge | **AWS sa-east-1** (São Paulo) | Account, profile, activities, custody, audit logs | LGPD Art. 33 § 1° IX (execução de contrato) — stored in BR, no transfer |
| Sentry      | Error + perf telemetry          | `sentry.io` (US) | Stack traces, user_id (opaque), IP (truncated), release SHA | LGPD Art. 33 V (garantia de cumprimento) + SCCs — transfer |
| Vercel      | Next.js portal edge runtime     | Global CDN (US-primary, edge in BR) | Request headers, path, IP | LGPD Art. 33 V + Vercel DPA with SCCs |
| Resend/SG   | Transactional email             | `resend.com` / `sendgrid.net` (US) | Email address, display name, email body | LGPD Art. 33 V + SCCs |
| Stripe      | Card acquiring                  | `stripe.com` (US, global) | Card-derived token, billing address, email | LGPD Art. 33 § 1° I (consent) + SCCs |
| Asaas       | PIX / boleto (BR-only users)    | `asaas.com` (BR) | CPF, name, email, phone | No transfer (BR datacenter) |
| Strava      | Activity source / OAuth         | `strava.com` (US, global) | OAuth token, activity streams | LGPD Art. 33 § 1° I (consent; user connects explicitly) + Strava DPA |
| GitHub CI   | Build + artifact caching        | `github.com` (US) | Repo contents (no prod PII) | No personal-data transfer — source code only |

> Note on Supabase region: **since 2026-03** we are on `sa-east-1`
> (documented in `docs/compliance/BACKUP_POLICY.md` §6). The earlier
> L04-10 audit captured the finding while the project was still on
> the US default. Migration to BR eliminated the largest single
> transfer volume; the remaining US transfers are **observability
> + payments + strava**, each individually justified below.

## 2. Safeguards per processor

### 2.1 Supabase (BR — no transfer today)

- Region: AWS `sa-east-1`.
- DPA: <https://supabase.com/dpa> — signed via the self-serve
  toggle on our organisation's billing page (acceptance recorded
  in `docs/compliance/dpa-records/supabase-2026-03-12.pdf`; file
  placeholder — populate once we have a real PDF).
- ROPA entry: `docs/compliance/ROPA.md` §2.1 (this document creates
  the cross-reference; the ROPA itself is a separate deliverable).
- LGPD basis: execution of the data-subject-Omni-Runner contract
  (Art. 7 V).

### 2.2 Sentry (US transfer)

- DSN region: `o<org>.ingest.sentry.io` (US).
- DPA: <https://sentry.io/legal/dpa/> — signed electronically on
  account setup. Counterparty: Functional Software, Inc. dba
  Sentry.
- SCCs: Sentry Module 2 (Controller → Processor) SCCs are
  incorporated by reference in the DPA.
- PII minimisation (see L20-05 runbook):
  - `beforeSend` strips cookies, full URLs (we redact query string),
    `Authorization` headers, any body matching our PII regex set.
  - `user.ip_address` is captured as `null` → Sentry auto-truncates.
  - Breadcrumbs skip request/response bodies.
- Data retention at Sentry: 90 days (our plan default).
- ROPA entry: `docs/compliance/ROPA.md` §2.2.

### 2.3 Vercel (US-primary, edge in BR)

- DPA: <https://vercel.com/legal/dpa> signed on org sign-up.
- Edge location for BR traffic: `gru1` (São Paulo). Requests from
  BR stay in BR for routing; only build artefacts cross borders.
- SCCs included.
- No application payload (POST bodies) is persisted by Vercel
  beyond edge caching TTLs (≤ 24h).

### 2.4 Resend / SendGrid (US)

- DPA: signed on account creation, US-based processors.
- SCCs included.
- Retention: delivered-message metadata for 30 days; full body
  not retained after send unless failure → retained for
  diagnostic 7 days.
- Templates are PII-minimised (first name + link, no PII in
  subject / preheader).

### 2.5 Stripe (US, global)

- DPA: <https://stripe.com/legal/dpa> — SCCs Module 1 + 2.
- Region: global; cardholder data handled by Stripe under
  PCI-DSS Level 1.
- We never receive PAN data; only Stripe-provided tokens.
- LGPD basis: explicit consent at checkout + contractual need.

### 2.6 Asaas (BR)

- No cross-border transfer — processor is Brazilian.
- DPA: signed in our Asaas dashboard 2026-02-04.
- Asaas retains the Brazilian-issued CPF/CNPJ for fiscal
  compliance (Brazilian law, not LGPD transfer).

### 2.7 Strava (US)

- User grants consent explicitly via OAuth. We store access +
  refresh tokens.
- DPA: Strava API terms include a DPA-equivalent clause:
  <https://www.strava.com/legal/api>.
- SCCs: Strava self-certified with EU-US DPF. For BR, we rely on
  user consent (Art. 33 § 1° I) plus revocation flow (L04-09).

### 2.8 GitHub (US) — no personal-data transfer

- Production PII never reaches GitHub.
- CI secrets are GitHub Encrypted Secrets; PII in tests is
  synthetic.
- Audit trail: GitHub audit log retained 90 days (organisation
  plan).

## 3. ANPD stance

- LGPD Art. 33: for countries without an ANPD adequacy decision,
  we rely on **standard contractual clauses (SCCs)** per Art. 33 II.
  The Brazilian equivalent of EU SCCs has been published by ANPD
  in 2024 (Resolução CD/ANPD nº 19/2024). Each processor above
  either adopts the ANPD SCCs directly (Supabase, Vercel) or
  incorporates them by reference in its DPA.
- When a processor refuses to sign ANPD SCCs, we fall back to
  **consent (Art. 33 § 1° I)** with a clear opt-in at the feature
  level (Strava) or **execution of the contract
  (Art. 33 § 1° IX)** when the feature cannot be delivered
  without the transfer (Stripe card acquiring).

## 4. ROPA cross-reference

Each processor must have a matching entry in
`docs/compliance/ROPA.md` with:

- Purpose of processing
- Data categories
- Data subjects
- Recipients (this processor)
- International transfer (Y/N + country/region)
- Retention
- Security measures

When a processor is added or removed, this document and the ROPA
must update together — the CI guard refuses a merge that updates
one without the other. (ROPA enforcement is tracked by follow-up
`L04-10-ropa-parity` since ROPA does not yet exist in the repo;
today the guard only enforces this document.)

## 5. Change procedure

Adding a new processor that receives personal data requires:

1. A PR that:
   - updates this document (new row in §1, new subsection in §2);
   - updates `ROPA.md`;
   - confirms the DPA is signed and cross-linked;
   - updates the CI guard's expected processor list (to be added
     when `ROPA.md` lands).
2. DPO delegate approval on the PR.
3. A posted announcement in `#legal` once merged.

Removing a processor:

1. Revoke the DPA at the provider (where applicable).
2. Export and delete all data held by that processor within 30
   days of revocation.
3. Update this document + ROPA.

## 6. Decision log

- **2026-04-21** — Policy first published. All processors listed
  have DPAs signed; Supabase migration to `sa-east-1` complete.
  Outstanding questions:
  - Resend vs SendGrid — we are actively evaluating; the policy
    covers both because both are in use during the A/B.
  - Strava on ANPD SCCs — Strava does not currently advertise
    ANPD-specific clauses. We rely on EU-US DPF + explicit
    consent. If ANPD refuses this combination in a future
    resolution, we will need to move Strava-dependent features
    behind an explicit LGPD opt-in screen. Tracked as
    `L04-10-strava-anpd`.

## 7. Cross-links

- [`L04-10 finding`](../audit/findings/L04-10-transferencia-internacional-de-dados-supabase-us-sentry-us.md)
- [`BACKUP_POLICY.md`](./BACKUP_POLICY.md) — retention windows that
  affect how long transferred data persists abroad.
- [`L20-05 runbook`](../runbooks/SENTRY_PII_REDACTION_RUNBOOK.md)
  (follow-up — Sentry PII redaction).
- [`L04-09 runbook`](../runbooks/THIRD_PARTY_REVOCATION_RUNBOOK.md)
  — Strava revocation that must precede deletion.
