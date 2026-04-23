# SQLCipher EOL — Operational Runbook (L11-07)

> **Audience:** Mobile / Platform / Security on-call.
> **Scope:** Operating and eventually migrating away from
> `sqlcipher_flutter_libs: 0.7.0+eol` in `omni_runner`.
> **Related:** ADR-009 (migration plan), L11-06 (dependency pinning),
> L11-05 (secure storage policy), L11-08 (Flutter SDK pinning),
> L01-30/31 (Android release hardening — ProGuard `§7 Drift + SQLCipher`).

## 1. Why this runbook exists

`sqlcipher_flutter_libs` was marked **end-of-life** with the
`0.7.0+eol` release. The bundled native SQLCipher binary is frozen at
that moment and will receive **no further security patches** from the
maintainer. See **ADR-009** for the full threat model, migration
options, and exit criteria.

This runbook tells you what to do in each operational scenario:

- How to know the pin has NOT drifted.
- How to respond when a CVE is disclosed.
- How to handle a well-intentioned engineer's "let me upgrade this" PR.
- How to execute the migration when a trigger fires.

## 2. What's in tree right now

| Artifact | Path | Purpose |
|----------|------|---------|
| pubspec pin + warning comment | `omni_runner/pubspec.yaml` (`sqlcipher_flutter_libs: 0.7.0+eol`) | Exact version, guarded by CI, docs in the pubspec itself. |
| ADR | `docs/adr/009-sqlcipher-eol-migration.md` | Decision record + migration options A/B/C. |
| Runbook (this file) | `docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md` | Playbooks. |
| CI guard | `tools/audit/check-sqlcipher-eol.ts` (`npm run audit:sqlcipher-eol`) | Rejects PRs that re-caret, re-range, or drop the pin. |
| Dependabot silence | `.github/dependabot.yml` (`drift-and-storage` group) | Blocks noisy auto-PRs. |
| DB key store | `omni_runner/lib/core/secure_storage/db_secure_store.dart` | Generates + stores the 256-bit encryption key in FlutterSecureStorage. |
| DB bootstrap | `omni_runner/lib/data/datasources/drift_database.dart` (`_openConnection`, `setEncryptionKey`) | Applies `PRAGMA key = "x'hex'"` at open time. |

**Do not touch any of the above without reading ADR-009.**

## 3. The CI guard — `check-sqlcipher-eol.ts`

Enforced on every PR via `npm run audit:sqlcipher-eol`. It verifies
(all must pass):

1. `omni_runner/pubspec.yaml` contains a line matching
   `^\s*sqlcipher_flutter_libs:\s*0\.7\.0\+eol\s*(?:#.*)?$`.
   Any caret (`^`), tilde (`~`), range operator (`>=`, `<=`, `>`, `<`,
   `-`), OR (`||`), wildcard (`*`, `x`), or alias (`git:`, `path:`,
   `hosted:`, `sdk:`) fails.
2. A non-empty warning comment block precedes the pin line
   (so the intent is visible at edit-time, not just at CI-time).
3. `docs/adr/009-sqlcipher-eol-migration.md` exists.
4. This runbook (`docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md`) exists.
5. `.github/dependabot.yml` contains `sqlcipher_flutter_libs` in the
   `drift-and-storage` ignore group.

Exit `0` means clean; exit `1` means at least one violation. The
violation message points to the exact remediation (re-pin, restore
ADR, restore runbook, restore ignore group).

## 4. Playbooks

### 4.1 A Flutter contributor raises "this is EOL, should we upgrade?"

**Response**: point them at **ADR-009 §Decision**. The decision is
**pin and watch**, not upgrade. If they think a trigger has fired
(see ADR-009 §Exit criteria), open an issue tagged `sqlcipher-eol`
with the trigger evidence (CVE link, Play Store rejection email,
security review findings) — do NOT proceed to upgrade without a
recorded trigger.

### 4.2 A security advisory fires for SQLCipher or SQLite

Security on-call path:

1. **Triage the advisory**:
   - Is it SQLCipher core or SQLite?
   - Does it affect code paths we exercise? Check `drift_database.dart`
     — we use: `PRAGMA key = "x'hex'"`, standard Drift SQL (SELECT
     / INSERT / UPDATE / DELETE, no user-supplied raw SQL), and
     blob I/O for GPS traces.
   - What is the CVSS score?
2. **Apply ADR-009 §Exit criteria**:
   - CVSS < 7.0 AND code path not exercised → comment in the
     runbook history, no action.
   - CVSS ≥ 7.0 AND code path exercised → **start migration (step 4.5)**.
3. **File an incident ticket** with the advisory ID, CVSS, affected
   paths, and decision. Link from ADR-009 §Exit criteria.
4. **Mobile release hold**: if migration is required, freeze mobile
   releases until the AES-GCM envelope (Option A) lands.

### 4.3 Dependabot opens a PR for `sqlcipher_flutter_libs`

Dependabot should NOT do this (the `drift-and-storage` group is
configured to skip this package). If it happens anyway:

1. **Close the PR** with comment: "sqlcipher_flutter_libs is EOL,
   see ADR-009 / L11-07. Dependabot should be ignoring it — fix the
   group configuration instead."
2. **Patch `.github/dependabot.yml`**: ensure the
   `drift-and-storage` group still lists `sqlcipher_flutter_libs` in
   its pattern. If a new fork was published and Dependabot picked up
   the fork's name (unlikely — we exact-pin), add the fork to the
   ignore list AND file an issue to audit whether the fork is
   squatting the plugin's name.

### 4.4 CI fails `audit:sqlcipher-eol`

Root-cause the failure:

- **"pin drift"** (`sqlcipher_flutter_libs: ^0.7.0+eol` or any other
  range) → restore `sqlcipher_flutter_libs: 0.7.0+eol` (exact). The
  engineer was almost certainly running `flutter pub upgrade --major-versions`
  or `dart pub add` which re-caret-prefixes by default.
- **"missing warning block"** → restore the multi-line comment
  block above the pin line (copy from git history or from ADR-009
  §"What this means concretely" #1).
- **"missing ADR"** / **"missing runbook"** → the engineer deleted
  the file, likely during a cleanup. Restore from git history.
- **"missing dependabot ignore"** → restore the
  `sqlcipher_flutter_libs` entry under the `drift-and-storage`
  group in `.github/dependabot.yml`.

If the root cause is "we're actually migrating", follow 4.5.

### 4.5 Executing the migration (exit-criterion triggered)

**Precondition**: a trigger from ADR-009 §"Exit criteria" has fired
AND a tracking issue / ticket exists with the trigger evidence.

Follow **ADR-009 §"Migration target"** — preferred is **Option A**
(drop SQLCipher, use `sqlite3_flutter_libs` + app-layer AES-GCM).
High-level sequence:

1. **Branch naming**: `fix/l11-07-ext-migrate-sqlcipher-<trigger>`.
2. **Pubspec swap**: add `sqlite3_flutter_libs: <exact>` + drop
   `sqlcipher_flutter_libs`. Keep the pin discipline (exact version,
   L11-06 auto-enforces via `.npmrc`-equivalent for pub isn't a
   thing, but tracking-ADR + guard update applies).
3. **Data migration**: Ship a one-shot migrator on app boot:
   - Detect legacy encrypted DB (file header `SQLite format 3`
     decrypts with the current PRAGMA-key key).
   - Decrypt via the old SQLCipher path (temporary parallel import).
   - Re-encrypt via AES-GCM envelope and write to new location.
   - On success, atomically rename + delete the legacy file.
   - On failure, preserve the legacy file AND surface a "DB
     migration failed" telemetry event; do NOT block app launch
     (user gets a fresh DB but we ship a recovery flow).
4. **Remove `PRAGMA key = "x'…'"` path** from `drift_database.dart`
   (closes C-03 from POST_REFACTOR_SECURITY_AND_RELIABILITY).
5. **Update CI guard**: drop `check-sqlcipher-eol.ts` or re-target it
   to the new package (follow `check-npm-dependency-pinning.ts`
   pattern for pub packages).
6. **Update ADR-009** — set `Status: Superseded by ADR-<N>` and
   create ADR-<N> documenting the migration actually executed.
7. **Release cadence**: migration lands in a SINGLE mobile release
   behind a feature flag (`feature_flags.migrateDbToAesGcm`). Roll
   out gradually (5% → 25% → 50% → 100%) over 1 week.

### 4.6 A fork of `sqlcipher_flutter_libs` is proposed

Sometimes a community member publishes a fork. Review path:

1. **Do NOT merge a PR that switches to a fork without a full
   security review.** The fork is a single-maintainer supply-chain
   risk — in aggregate, often WORSE than pinned EOL with a known
   provenance (see ADR-009 §Option C).
2. If the fork has ≥ 6 months of consistent releases AND a
   published threat model AND is actively integrated by Drift
   upstream → reconsider ADR-009 and open an issue.
3. Otherwise, document "reviewed fork `<name>`, rejected
   `<date>`, reason `<...>`" in ADR-009 §"Exit criteria" and leave
   the pin in place.

### 4.7 An internal security review flags the EOL plugin

1. Review the audit finding against ADR-009 §"Threat model".
2. If the reviewer's concern is one of the three CVE categories
   (key derivation, SQL parser, memory safety) AND has a concrete
   current CVE → treat as 4.2.
3. If the reviewer's concern is generic "EOL is bad" → link
   ADR-009 §"Decision" and §"Exit criteria". We ARE watching;
   we are NOT migrating proactively.
4. If the reviewer has standing to force the migration (e.g., an
   institutional customer), trigger 4.5 via an explicit business
   ticket.

## 5. Detection signals (what to watch in dashboards)

| Signal | Source | Threshold | Action |
|--------|--------|-----------|--------|
| GitHub advisory for `sqlcipher/sqlcipher` | GHSA feed | Any | 4.2 |
| GitHub advisory for `sqlite/sqlite` | GHSA feed | CVSS ≥ 7.0 | 4.2 |
| `audit:sqlcipher-eol` CI failure | CI | Any | 4.4 |
| Play Store / App Store rejection mentioning "outdated crypto libraries" | Store reviewer feedback | Any | 4.5 trigger |
| Drift / sqlite3_flutter_libs release notes mention SQLCipher migration advice | Drift releases | Manual watch monthly | Revisit ADR-009 |
| Dependabot PR opened for `sqlcipher_flutter_libs` | PR bot | Any | 4.3 |

## 6. Rollback

There is no "rollback" of the pin — it's already on the only
version that will ever ship under this name. If we've migrated
(step 4.5) and need to revert:

1. Revert the migration PR chain on mobile (use the feature flag
   to disable `migrateDbToAesGcm` in 100% of cohorts).
2. Users on the new cohort keep the AES-GCM DB (they've already
   migrated — no data loss), but new app starts use the legacy
   SQLCipher path.
3. Restore this runbook and ADR-009 from the post-migration ADR's
   "Superseded by" reference.
4. File a new finding L11-07-v2 describing the rollback trigger.

## 7. Cross-references

- **L11-06** — NPM dependency pinning. Same philosophy (exact pin
  + CI guard + runbook), but NPM instead of pub.
- **L11-05** — Secure storage policy. The FlutterSecureStorage
  entry for the DB encryption key is governed by `PrefsSafeKey`;
  this runbook's migration cannot silently leak the key because
  L11-05's guards still apply.
- **L11-08** — Flutter SDK pinning. When that lands, it adds a
  third rail: `sdk: '>=3.8.0 <4.0.0'` gets tightened and a major
  Flutter bump forces us to evaluate this plugin's NDK/toolchain
  compatibility (ADR-009 §Exit criterion #2).
- **L01-30 / L01-31** — Android release hardening. ProGuard
  `§7 Drift + SQLCipher` rules keep SQLCipher's native bindings
  un-obfuscated; those rules stay correct for the pinned version.
- **C-03** — PRAGMA key raw-hex format (`docs/POST_REFACTOR_SKEPTICAL_PASS.md`).
  The migration to Option A closes C-03; until then the `PRAGMA key
  = "x'hex'"` path remains the mitigation.
