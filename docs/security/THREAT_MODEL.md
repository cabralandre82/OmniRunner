# Omni Runner — threat model (STRIDE + DFD)

> **Scope:** Omni Runner platform as it exists in this repository on
> 2026-04-21 (Sprint 25.0.0, Strava-only architecture).
> **Finding:** [`L10-02`](../audit/findings/L10-02-threat-model-formal-nao-documentado.md)
> **Owner:** Security rotation (today: founder).
> **Review cadence:** after every major feature **or** every 90 days,
> whichever comes first (see §9).
> **Guard CI:** `npm run audit:threat-model`.

---

## 1. System overview

Omni Runner is a running-focused coaching + custody platform with:

- Mobile apps (Flutter) that **no longer** perform live GPS tracking;
  all activity data arrives via Strava (`docs/ARCHITECTURE.md` §7).
- Portal (Next.js on Vercel) used by staff (platform), coaches
  (assessoria), and athletes.
- Supabase (Postgres + Auth + Edge Functions + Storage) as the
  primary data store and API gateway.
- Third-party processors: **Strava** (activity source),
  **Stripe** + **Asaas** (payments), **Sentry** (error telemetry),
  **Resend / SendGrid** (email).
- OmniCoin — an internal credit/points unit with 1 coin ≈ 1 USD
  purchasing power for cosmetic items (never withdrawable as cash
  today; L09-01 tracks the BCB classification question).

## 2. Data-flow diagram (textual)

```
                  ┌──────────────────┐
                  │  User devices    │
                  │ (Flutter / Web)  │
                  └────────┬─────────┘
          ┌────────────────┼──────────────┐
          │                │              │
          ▼                ▼              ▼
    [A] Strava API    [B] Supabase   [C] Portal edge
    (OAuth, webhook)  (Auth + PostgREST  (Next.js on
                      + Realtime +       Vercel)
                      Edge Functions)
                           │
                           ▼
                    [D] Postgres
                  ┌─────────┴────────────┐
                  │  public.*            │
                  │  (coin_ledger,       │
                  │   custody_accounts,  │
                  │   sessions, ...)     │
                  │  public_olap.*       │
                  │   (MVs; L08-06)      │
                  └─────────┬────────────┘
                           │
               ┌───────────┼────────────┐
               │           │            │
               ▼           ▼            ▼
          [E] Stripe   [F] Asaas   [G] Sentry
          (card in)    (PIX / BR   (errors + PII
                       billing)     redaction — L20-05)
```

### 2.1 Actors

- **Athlete** — end user on mobile; authenticated via Supabase Auth.
- **Coach / professor** — authenticated user with role
  `coaching_members.role ∈ {'admin_master', 'professor'}`.
- **Platform staff** — `platform_admin` role (L10-06 is splitting
  this into sub-roles); can inspect any tenant.
- **Strava user** — external OAuth identity linked via
  `public.strava_tokens`.
- **Attacker** — external, anonymous or pretending to be any of the
  above.

### 2.2 Trust boundaries

- **TB1** — Device ↔ network. Attacker in the middle (Public Wi-Fi,
  hostile network). Mitigated by TLS everywhere; HSTS on all domains
  we control.
- **TB2** — Mobile app ↔ Supabase. Bearer JWT; RLS is authoritative
  (L10-06).
- **TB3** — Portal browser ↔ Next.js. Cookie-based session;
  `SameSite=Lax`; CSRF double-submit where required.
- **TB4** — Next.js ↔ Supabase. Two clients: anon client with user
  JWT (RLS enforced) and service-role client
  (`createAdminClient()`, RLS bypassed — this is the highest-risk
  boundary; L10-03 tracks distribution; L10-06 tracks SoD).
- **TB5** — Supabase ↔ third-party. Server-side webhook signatures
  (Stripe, Asaas), OAuth PKCE (Strava), outgoing Authorization
  headers. Server-only keys.
- **TB6** — Data subject ↔ backup. Backups retained at provider;
  L04-08 tracks the retention policy and encryption-at-rest
  verification.

## 3. Assets (ranked by blast radius if compromised)

1. **OmniCoin ledger** (`public.coin_ledger`, partitioned monthly
   since L19-01). Custody of users' purchased credits.
2. **Custody accounts** (`public.custody_accounts`) —
   group-level USD balances (deposits / commitments / settlement).
3. **Activities** (`public.sessions`, `public.strava_tokens`) —
   run history + linked Strava tokens.
4. **Authentication state** (`auth.users`, `auth.sessions`,
   Supabase JWT secret).
5. **Service-role key** (Supabase) — bypasses RLS; compromise
   is effectively root.
6. **PII** — profiles, emails, possibly CPF/CNPJ if KYC ships
   (L09-02), phone, social handles (L04-06).
7. **Audit trail** (`public.audit_logs`, `public.portal_audit_log`,
   `public_olap.mv_refresh_runs`) — append-only (L10-08); integrity
   is the asset, not secrecy.

## 4. STRIDE by trust boundary

Legend: mitigation status — ✅ shipped / 🟡 partial / ⏳ in roadmap.

### 4.1 TB1 — Device ↔ network

| Threat | STRIDE | Mitigation | Status |
|---|---|---|---|
| TLS MITM → session hijack | S, T, I | TLS 1.2+ only, HSTS, certificate pinning in Flutter (L13-09) | ✅ |
| Downgrade to HTTP | T | HSTS preload on `omnirunner.com` | ⏳ L20-09 |
| Captive portal injects HTML | T, I | All auth on native app, not embedded webview | ✅ |

### 4.2 TB2 — Mobile app ↔ Supabase

| Threat | STRIDE | Mitigation | Status |
|---|---|---|---|
| JWT stolen from device storage | S, I | EncryptedSharedPreferences on Android, Keychain on iOS (L01-01) | ✅ |
| Replay of signed request | T | TLS + JWT `iat`/`exp` (Supabase default) | ✅ |
| Bypass RLS by forging claims | S | `request.jwt.claim.*` validated by Supabase; critical RPCs re-check (L10-07 `jwt-claims-validation` guard) | ✅ |
| Resource exhaustion (write-flood) | D | Rate limiting on Edge Functions + RPC-level checks (L06-08) | 🟡 |
| Broken deep-link opens intent from attacker | S | Intent filters scoped to https domain we own (L13-09 pending) | 🟡 |

### 4.3 TB3 — Portal browser ↔ Next.js

| Threat | STRIDE | Mitigation | Status |
|---|---|---|---|
| XSS → steal session cookie | S, I, E | React default escaping; CSP with strict-dynamic (L10-05) | 🟡 |
| CSRF on state-changing route | T | Double-submit cookie on `/api/*` POST/PUT (L07-04) | ✅ |
| Clickjacking / UI redress | T | `X-Frame-Options: DENY` (L10-05) | 🟡 |
| SSRF from a server action | T, I | Allow-list of outbound targets; internal-only URLs rejected | ⏳ L10-05 |

### 4.4 TB4 — Next.js ↔ Supabase (service-role boundary)

| Threat | STRIDE | Mitigation | Status |
|---|---|---|---|
| Service-role key leak | S, T, I, E | Env-var only, never client-side; CI guard for `SUPABASE_SERVICE_ROLE_KEY` in client code (L10-03) | 🟡 → ⏳ |
| Service-role used where RLS would suffice | E | `createAdminClient()` usage is searched; each call needs comment (L10-03 guard) | ⏳ |
| `platform_admin` acts as both approver and requester | E | SoD split shipped by L10-06 (roles: `platform_admin_reviewer`, `platform_admin_approver`) | ⏳ |
| Append-only audit table modified | T, R | L10-08 trigger blocks UPDATE/DELETE/TRUNCATE; retention has a strict DELETE-only bypass (L08-08) | ✅ |
| Actor denies having performed a privileged action | R | Every privileged RPC writes to `public.audit_logs` / `public.portal_audit_log` with `actor_id`, `ip`, `user_agent`, `acted_at`; L10-08 makes that trail immutable | ✅ |

### 4.5 TB5 — Supabase ↔ third-party

| Threat | STRIDE | Mitigation | Status |
|---|---|---|---|
| Webhook replay (Stripe/Asaas) | T | Provider-signed HMAC + our idempotency keys (coin_ledger_idempotency) | ✅ |
| Strava token theft → mass data pull | I | Tokens stored encrypted, revocation on user request (L04-09) | 🟡 → ⏳ |
| Asaas API key leak | I, E | Key rotation runbook; at-rest encryption (L09-06) | ⏳ |
| Third-party outage cascades to us | D | Public status page aggregator with worst-wins levels (L20-06) | ✅ |

### 4.6 TB6 — Data subject ↔ backup

| Threat | STRIDE | Mitigation | Status |
|---|---|---|---|
| Backup retained forever beyond LGPD window | I | Documented retention + runbook (L04-08) | ⏳ |
| Backup exfiltration at provider | I | Provider encrypts-at-rest; our share includes no plaintext service-role key | ✅ |

## 5. Severity bump rules

The STRIDE table produces a raw severity. We apply these bumps
before publishing the CVSS to the reporter (L10-01):

- **+1** if the threat directly moves funds or modifies
  `coin_ledger` rows (TB2 RLS forge, TB4 service-role).
- **+1** if the threat crosses tenants (TB4 `platform_admin` acting
  outside its SoD).
- **-1** if exploitation requires a **compromised** provider
  credential **and** a **compromised** device — double root.

## 6. Mitigation traceability

Every mitigation must be traceable to:

1. A commit or a merged PR **or** a documented decision (ADR) **or**
   a published runbook.
2. A CI guard **or** a migration-level assertion where possible.
3. A finding ID (`Lxx-yy`) if it closed an audit row.

The mapping is the source of truth in
[`docs/audit/registry.json`](../audit/registry.json) via each
finding's `linked_prs`.

## 7. Abuse cases (attacker stories)

1. **"Refund a burn after the fact"** (TB4, TB2).
   Attacker creates a legit purchase, then tries to force
   `reverse_burn_atomic` without a matching original.
   Mitigation: L19-06 idempotency + reverse helper
   requires the original txn ref.
2. **"Drain custody into withdraw"** (TB4).
   Attacker with `platform_admin` tries to approve their own
   withdraw. Mitigation: L10-06 SoD split (pending).
3. **"Replay a Strava webhook"** (TB5).
   Attacker resends a signed Strava event after token revocation.
   Mitigation: idempotency key + revoked-token check (L04-09).
4. **"Modify an audit row"** (TB4). Mitigation: L10-08 append-only
   trigger with DELETE-only retention bypass (L08-08).
5. **"Brute-force login"** (TB3, TB2). Mitigation: L06-06 anti-
   credential-stuffing; captcha on suspicious IP.
6. **"Elite athlete flagged publicly"** (L21-10 — reputation
   system). Mitigation: private quarantine + appeal flow
   before any public marking.

## 8. What is *not* in this threat model (yet)

- Supply-chain attacks on our CI dependencies — tracked partially
  by L10-04 / L06-07 (SRI + npm pinning).
- Insider threat beyond SoD — we do not yet require
  four-eyes for `platform_admin` actions; when company grows,
  revisit.
- Physical attacks at provider data centres — covered by the
  provider's own SOC 2, out of scope for our review.

## 9. Review cadence

- **After every major feature** (defined as: a migration touching
  custody/ledger; or a new external integration; or a change
  to the service-role boundary).
- **Every 90 days** as a calendar trigger (owner: security
  rotation).
- **On every High/Critical finding closure** — revisit the
  corresponding STRIDE row and update the status column.

Record review outcomes in §10 below.

## 10. Review history

- `2026-04-21` — Initial version. Published together with
  `SECURITY.md` (L10-01). Current bumper-to-bumper walk:
  - TB2: critical mitigations ✅; deep-link intent scoping still 🟡.
  - TB4: service-role distribution still 🟡 → ⏳ L10-03.
  - TB4: SoD on `platform_admin` still ⏳ L10-06.
  - TB5: Asaas key at-rest encryption still ⏳ L09-06.
  - TB6: backup retention policy still ⏳ L04-08.
  - Strava-only sprint (Sprint 25.0.0) removed TB2 rows about
    live GPS tracking (reclassified to `wont-fix` in the audit
    sweep 2026-04-21).

## 11. Cross-links

- [`SECURITY.md`](../../SECURITY.md) — public disclosure policy (L10-01).
- [`L10-02 finding`](../audit/findings/L10-02-threat-model-formal-nao-documentado.md)
- [`L10-03 finding`](../audit/findings/L10-03-service-role-key-distribuida-amplamente.md)
  — TB4 hardening.
- [`L10-06 finding`](../audit/findings/L10-06-segregacao-de-funcao-sod-ausente-em-platform-admin.md)
  — TB4 SoD.
- [`L10-08 migration`](../../supabase/migrations/20260421350000_l10_08_audit_logs_append_only.sql)
  — audit immutability.
- [`docs/ARCHITECTURE.md §7`](../ARCHITECTURE.md) — Strava-only
  architectural decision that removed several TB2 rows.
