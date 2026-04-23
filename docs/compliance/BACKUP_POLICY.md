# Backup & restore policy — Omni Runner

> **Finding:** [`L04-08`](../audit/findings/L04-08-backups-supabase-sem-politica-de-retencao-documentada.md)
> **Owner:** Platform / SRE rotation.
> **Review cadence:** annual, or within 30 days of any change to
> provider plan / restore tooling / LGPD guidance.
> **Guard CI:** `npm run audit:backup-policy`.

---

## 1. Scope

Covers backup, restore, and disaster-recovery (DR) procedures for:

- Supabase Postgres database (`public.*`, `public_olap.*`,
  `auth.*`, `storage.*`).
- Supabase Storage buckets (profile pictures, workout exports).
- Application-level exports (`athlete_monthly_report`, OLAP MVs).

Out of scope:

- Third-party data held by Strava, Stripe, Asaas, Sentry — governed
  by their own agreements. We keep only the minimum needed for
  reconciliation (webhook IDs, external IDs).
- User-device backups (iCloud, Google Drive). End users control
  those.

## 2. Retention matrix

| Class                          | Window        | Medium             | Notes |
|--------------------------------|---------------|--------------------|-------|
| Point-in-time recovery (PITR)  | **7 days**    | Supabase PITR WAL  | Paid plan. Rolling window. |
| Daily snapshots                | **14 days**   | Supabase snapshot  | Default tier. |
| Weekly snapshots               | **30 days**   | Exported nightly   | Encrypted-at-rest, off-cluster. Runbook §5. |
| Monthly snapshots              | **180 days**  | Cold storage       | Compliance / fiscal replay. §3.3. |
| Audit-log retention (in-table) | see L08-08    | Postgres           | Different axis — per-table retention in `audit_logs_retention_config`. |

If the provider plan changes (e.g., we upgrade or downgrade), the
numbers in §2 change. That change is a **controlled** change:
it requires a PR that touches this document AND the CI guard
expectations so they stay in sync.

## 3. LGPD alignment

### 3.1 Right to erasure (LGPD Art. 18 VI)

When a user exercises the right to erasure:

1. We delete the user from **live** tables immediately (cascades
   via FK `ON DELETE CASCADE` where appropriate — see `auth.users`
   FKs in `20260218000000_full_schema.sql`).
2. We **do not** rewrite backups. LGPD does not require us to;
   ANPD guidance confirms backups are a legitimate exception
   provided retention is bounded and documented (this document
   fulfils the "documented" requirement).
3. We **block restore** from any backup taken before the
   erasure request for **30 days after** the erasure was
   confirmed. If a disaster requires restoration during that
   window, the subject's row is scrubbed immediately after
   restore, before any user-facing service comes back online.
   Runbook §6 details the scrubbing steps.
4. After **180 days** (the maximum retention window above), no
   backup can contain the erased subject's identifiable data.
   The worst-case exposure is thus 180 days from the erasure
   request.

### 3.2 Right to data portability (LGPD Art. 18 V)

Portability is served from **live** tables through the
athlete monthly report exports. Backups are never used as the
source for portability requests.

### 3.3 Fiscal / regulatory retention conflict

When a retention rule from §2 conflicts with a fiscal retention
requirement (e.g., 5 years for invoices), the **longer** window
wins — the rows stay in the live table, governed by
`audit_logs_retention_config` (L08-08), not by backups.

Monthly snapshots (180 days) exist specifically to replay
fiscal data if a live-table corruption is discovered after the
14-day daily window has expired.

## 4. Staging environment

- Staging receives a **weekly** snapshot of production.
- PII is **ofuscated** on import:
  - `auth.users.email` → `user_<id>@stg.omnirunner.dev`.
  - `profiles.full_name` → `User <short-id>`.
  - Phone numbers → `+55 11 9xxxx-xxxx`.
  - CPF (if present, post-L09-02) → zeroed.
  - `profiles.instagram_handle` / `tiktok_handle` → cleared.
  - Strava tokens → invalidated; staging cannot act on real
    Strava accounts.
- Custody balances and coin_ledger entries are kept **as-is** so
  financial-flow tests reflect production distribution; the
  `user_id` links are preserved (they map to obfuscated auth.users
  rows).
- Staging refresh is operator-initiated, not scheduled. See
  runbook §7.

## 5. Restore drills

- At least **once per quarter**, we execute a dry-run restore
  into a sandbox project from the most recent daily snapshot.
- Success criteria: < 90 minutes wall clock from "decision to
  restore" to "sandbox is queryable", schema migration applied,
  smoke tests pass.
- The drill outcome is recorded in `docs/compliance/restore-drills/<YYYY-Qx>.md`.
  Missing a quarter is a **reportable** event — it becomes a
  finding automatically via the `audit:backup-policy` guard
  (once the drill log structure is populated; today the guard
  only enforces document presence, drill-log enforcement is a
  follow-up tracked as `L04-08-drill-log`).

## 6. Cross-border transfer

The Supabase region we operate in today is **AWS sa-east-1**
(São Paulo). Backups inherit that region. **No** automatic
cross-border replication is configured; any cross-border copy
is a conscious operator action governed by L04-10 DPA.

## 7. Decision log

- **2026-04-21** — Policy first published. PITR 7 days + daily
  14d + weekly 30d + monthly 180d matches Supabase Pro plan
  defaults with minimal surcharge for the monthly cold copy.
  Chosen over a 30-day PITR tier because the extra PITR days
  don't help LGPD alignment and cost ~3× more.

## 8. Cross-links

- [`L04-08 finding`](../audit/findings/L04-08-backups-supabase-sem-politica-de-retencao-documentada.md)
- [`L04-10 finding`](../audit/findings/L04-10-transferencia-internacional-de-dados-supabase-us-sentry-us-sem.md)
  — cross-border transfer clauses.
- [`L08-08 runbook`](../runbooks/AUDIT_LOGS_RETENTION_RUNBOOK.md)
  — per-table retention (different axis).
- [`L04-09 finding`](../audit/findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md)
  — third-party token revocation affects backup scrubbing window.
- Restore / scrubbing runbook —
  [`docs/runbooks/BACKUP_RESTORE_RUNBOOK.md`](../runbooks/BACKUP_RESTORE_RUNBOOK.md).
