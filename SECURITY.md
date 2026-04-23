# Security policy — Omni Runner

> This document describes how to report security issues in Omni Runner
> and what you can expect from us. If you believe you have found a
> vulnerability, **please read this document before disclosing anything
> publicly**.

- **Reference:** `docs/audit/findings/L10-01-nenhum-bug-bounty-disclosure-policy.md`
- **Machine-readable policy:** [`/.well-known/security.txt`](./portal/public/.well-known/security.txt)
- **Internal triage runbook:** [`docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md`](./docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md)
- **CI guard:** `npm run audit:security-disclosure`

---

## Reporting a vulnerability

Please **do not** open public GitHub issues, pull requests, tweets,
Discord posts or blog articles describing vulnerabilities in Omni
Runner until we have had a chance to ship a fix.

Send your report to **security@omnirunner.com** using one of the
following channels:

1. **Plain email** to `security@omnirunner.com`.
   - Include: affected URL / endpoint / file, reproduction steps,
     expected vs observed behaviour, and your preferred contact method.
   - Please **do not** include credentials, personal data of real
     users, or live production payloads in the report body. Redact
     before sending. If reproduction requires real data, say so and
     we will coordinate a secure channel.
2. **PGP-encrypted email** to the same address. Our PGP public key is
   published at [`/.well-known/security.txt`](./portal/public/.well-known/security.txt)
   (once first issued — if the key is not yet published, send plain
   email and we will respond with an encrypted channel).
3. **GitHub private advisory** (preferred if the issue concerns the
   public code in this repository):
   <https://github.com/cabralandre82/OmniRunner/security/advisories/new>

We accept reports in **Portuguese** and **English**.

## Scope

In scope:

- `omnirunner.com` and all `*.omnirunner.com` subdomains we operate.
- The Omni Runner mobile app (iOS and Android).
- Server-side code in this repository (Next.js portal, Supabase
  migrations, edge functions, CI tooling).
- Third-party integrations under our control (Strava webhook
  handshake, Asaas callback signature, Stripe webhook signature).

Out of scope:

- Issues in third-party services themselves (Supabase, Vercel,
  Stripe, Asaas, Strava, Sentry). Please report those to the
  respective providers. We will relay relevant findings if they
  affect us.
- Social engineering against Omni Runner staff.
- Physical attacks against our offices or cloud providers.
- DoS / volumetric tests that would degrade production for real
  users. Rate-limit probing at ≤ 10 req/s from a single source is
  acceptable.
- Findings that depend on a jailbroken / rooted device with no
  bypass of platform controls (e.g., reading SharedPreferences on
  a rooted Android device is out of scope; finding a way to do it
  on an unrooted device is **in** scope — see L01-01).
- Reports generated automatically by scanners without manual
  validation or a reproducible PoC.

## What we promise

- **Acknowledgement** within 3 business days (BRT, UTC-3).
- **Triage result** (severity classification + whether we consider it
  in scope) within 10 business days.
- **Status update** every 14 days until the report is closed, unless
  we explicitly agree on a different cadence with you.
- **Credit** in the release notes / advisory that ships the fix,
  unless you prefer to stay anonymous. Tell us which name / handle /
  affiliation you want credited.
- A **resolution SLA** that depends on the severity triage result
  (see below). If we cannot meet the SLA, we will tell you and
  explain why.

### Resolution SLAs

| Severity  | Triage target | Mitigation target | Full fix target |
|-----------|--------------:|------------------:|----------------:|
| Critical  | 24 hours      | 72 hours          | 14 days         |
| High      | 3 days        | 14 days           | 45 days         |
| Medium    | 7 days        | 30 days           | 90 days         |
| Low       | 10 days       | next release      | 180 days        |

Severity follows CVSS v3.1 as a starting point, adjusted for our
attack surface (e.g., financial RPCs — custody / coin_ledger — get
a +1 severity bump).

### Safe harbour

If you report in good faith under this policy, we will **not**:

- Initiate or support any legal action against you for the research
  activities required to find and validate the issue (as defined in
  the Scope section above).
- Ask your service provider to take down or disclose your identity.

This safe harbour does **not** cover: accessing, modifying, or
destroying data that is not your own; leaking data to third parties;
using the finding for extortion; or violating any laws of your
jurisdiction or ours.

## Bug bounty

We do **not** yet operate a public bug bounty program. After the
first external penetration test (tracked by finding `L10-02`), we
will evaluate a private program on **YesWeHack**, **Intigriti** or
**HackerOne**. Reports submitted in the interim will be rewarded
at our discretion — typically in OmniCoin credit, Omni Runner merch,
or (for high/critical issues) retroactive monetary rewards once the
program is launched.

## Hall of fame

Reporters who agree to be credited will be listed at
<https://omnirunner.com/security/hall-of-fame> (to be created as part
of the first credited report).

## Change history

- 2026-04-21 — First version of this policy. Published
  `/.well-known/security.txt`, `SECURITY.md`, and
  `docs/runbooks/SECURITY_DISCLOSURE_RUNBOOK.md`. Closes finding
  `L10-01`.
