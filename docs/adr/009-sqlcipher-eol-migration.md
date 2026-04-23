# ADR-009: SQLCipher End-of-Life — Pin-and-Watch Posture

**Status:** Accepted
**Date:** 2026-04-21
**Audit linkage:** L11-07 — `sqlcipher_flutter_libs: ^0.7.0+eol` — EOL.

## Context

`omni_runner/pubspec.yaml` depends on `sqlcipher_flutter_libs` for
SQLite at-rest encryption (Drift + SQLCipher, see ADR-001 and
`docs/POST_REFACTOR_SECURITY_AND_RELIABILITY.md` C-03). The upstream
package was explicitly marked **end-of-life** by its author (Simon
Binder, who also maintains Drift) with the `0.7.0+eol` release:

> This package no longer receives updates. Consumers are encouraged to
> migrate away from SQLCipher since it is no longer being maintained as
> an open-source project in a way that is practical to keep shipping
> from a Flutter-plugin perspective.

This leaves the app in the following state:

- The bundled SQLCipher C code is **pinned at the moment the plugin
  went EOL**. Any CVE disclosed after that date will NOT be patched
  upstream.
- The plugin binaries for Android / iOS / macOS / Linux are the last
  artifacts that will ever be shipped under this name on pub.dev.
- Dependabot and the Flutter toolchain will not propose upgrades
  (we already ignore minor/patch updates in `.github/dependabot.yml`,
  group `drift-and-storage`).
- We cannot simply drop encryption — the local DB stores workout
  history, GPS traces, and session tokens; LGPD (see L04-01…L04-09)
  requires encryption at rest.

### Threat model

The residual risk is **a SQLCipher CVE landing upstream AND it being
exploitable in a mobile-client context**. SQLCipher CVEs historically
land in categories:

1. Key-derivation weaknesses (e.g., PBKDF2 iteration counts). We
   already mitigate via the app-layer 256-bit key stored in
   FlutterSecureStorage (ADR `docs/POST_REFACTOR_SECURITY_AND_RELIABILITY.md`
   C-03), and use `PRAGMA key = "x'hex'"` raw-key format so KDF weaknesses
   do not apply. **Low residual.**
2. SQL parser bugs inherited from upstream SQLite. These land upstream
   in SQLite itself first and propagate via `sqlite3_flutter_libs`,
   which we could adopt in a migration. **Medium residual.**
3. Memory-safety bugs in SQLCipher's encryption extension (native
   cipher code). Rare historically. **Low residual but high impact.**

Given the mitigations already in place and the low historical CVE
rate on SQLCipher's cipher extension, a **pin-and-watch** posture is
acceptable for Onda 1. A full migration is a significant re-plumb
(touches `drift_database.dart`, native build, CI, and the migration
cutover must not lose encrypted user data) and is queued for Onda 2.

## Decision

**Pin `sqlcipher_flutter_libs` exactly to `0.7.0+eol` (no caret),
guard via CI, monitor for triggers, and keep the migration ADR
evergreen with a recommended replacement.**

### What this means concretely

1. **Exact pin** — `omni_runner/pubspec.yaml` uses
   `sqlcipher_flutter_libs: 0.7.0+eol` (no caret, no range). Guarded by
   `npm run audit:sqlcipher-eol` (`tools/audit/check-sqlcipher-eol.ts`).
2. **Dependabot silence** — `drift-and-storage` group in
   `.github/dependabot.yml` continues to ignore minor/patch bumps,
   AND the audit guard additionally rejects any `pubspec.yaml` edit
   that re-introduces a caret, tilde, or non-`0.7.0+eol` range.
3. **Documented migration plan** — this ADR + the operational runbook
   `docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md` keep the replacement
   evaluation evergreen. Any engineer triggered by one of the exit
   criteria below has a runbook-guided path, not a blank page.
4. **Migration tracked as Onda 2 work** — L11-07-ext (to be filed)
   covers the actual port. This ADR formally downgrades L11-07 to
   "supply-chain process fix" because the acute risk is
   "silent-pick-up of a malicious successor" (which the exact pin
   kills), and the residual "CVE exposure" is handled by the watch
   protocol.

### Migration target (when triggered)

Evaluated options, ordered by current preference:

| Option | Summary | Pros | Cons | Effort |
|-------|---------|------|------|-------|
| **A. `sqlite3_flutter_libs` + app-layer AES-GCM** (recommended) | Drop SQLCipher, switch Drift to `sqlite3_flutter_libs` (maintained), encrypt DB file at rest with AES-GCM using the existing FlutterSecureStorage key. | Maintained upstream; lower native surface; key-rotation simpler; no PRAGMA key SQL injection concern (L11-07's sibling C-03). | Requires a **one-time migration** of existing encrypted DBs: decrypt-via-sqlcipher → re-encrypt-via-AES-GCM. If migration fails, user loses local history. Needs careful resumable-migration logic. | L (8–13 points) |
| **B. Maintained SQLCipher fork via CMake in `sqlite3_flutter_libs`** | Drift's own upgrade guide suggests building SQLCipher from source via CMake inside `sqlite3_flutter_libs`. Stays closest to the current PRAGMA-key contract. | Minimal Dart-side churn; drop-in for the current PRAGMA-key code path; no data migration needed. | Forces us to own the native build pipeline; requires CMake toolchain per-platform (Linux/macOS/Windows CI); SQLCipher licensing questions resurface (we must ship SQLCipher's BSD 3-clause LICENSE files and NOTICE). | M (5–8 points) |
| **C. Community fork of `sqlcipher_flutter_libs`** | Adopt a maintained fork (e.g., a fork that keeps shipping CVE patches). | Drop-in, minimal churn. | Supply-chain risk is just **moved** — a single-maintainer fork with unknown release cadence is NOT a better position than pinned EOL. | S (2–3 points) |

**Preferred**: **A** (drop SQLCipher, use AES-GCM envelope at the
file-block layer via Drift's `DriftNativeOptions.setup` hook). This
also unblocks closing C-03 entirely (removes the `PRAGMA key = "x'…'"`
string-interpolation path).

**Not chosen now**: A full migration blocks on (i) a resumable DB
re-encryption plan and (ii) a mechanism for users to downgrade cleanly
during the rollout window. Those are ~2 weeks of work we are not
investing without a trigger.

### Exit criteria (migration MUST start within one sprint)

- A SQLCipher or SQLite CVE lands with CVSS ≥ 7.0 AND affects the
  code paths we use (`PRAGMA key`, core SQL parser, blob I/O).
- Flutter 4.x deprecates Android NDK targets below `r27`, forcing
  us to rebuild all native plugins — the EOL plugin will not be
  rebuilt and we inherit the blast radius.
- Google Play or App Store rejects an upload citing "bundled
  unmaintained crypto libraries".
- An internal security review forces the move.
- Any third-party customer (Cabral, institutional user) contractually
  requires "no EOL crypto libraries in the client".

Until one of these triggers, the pin-and-watch posture stands.

### Monitoring & signals

- **Weekly**: `tools/audit/check-sqlcipher-eol.ts` runs as part of
  `npm run audit:sqlcipher-eol` in CI. Surfaces any pin drift AND
  surfaces reminders that the EOL plugin is still in-tree.
- **On CVE**: Security team subscribes to `sqlcipher/sqlcipher` and
  `sqlite3/sqlite3` CVE feeds (GitHub Advisory DB tags
  `GHSA:pypy-sqlcipher*`, `CVE-YYYY-*`).
- **On release**: Drift author occasionally emits advisories; we
  watch `simolus3/drift` GitHub releases for SQLite/encryption
  advisories via Dependabot's advisory alert (not version-update) surface.

## Consequences

**Positive**

- Silent-pick-up of a malicious name-squat successor is **mechanically
  impossible** (exact pin + CI guard rejects ranges).
- No behavioural change to the app — same plugin, same PRAGMA-key
  code path, same encrypted DBs.
- The migration plan is tracked (this ADR + runbook + future
  L11-07-ext), not forgotten.
- Dependabot noise is reduced to zero for this package (already
  ignored in `drift-and-storage` group).

**Negative**

- The plugin's native SQLCipher blobs are **frozen**. If SQLite
  itself ships a CVE that would normally trickle down via
  `sqlite3_flutter_libs`, we do NOT inherit it for this plugin.
- We carry tech debt until Onda 2 (or a trigger event).
- Future engineers MUST read this ADR before touching anything
  around the encrypted DB (Drift repositories, `DbSecureStore`,
  the `PRAGMA key` path in `drift_database.dart`).

**Neutral**

- LGPD posture unchanged — encryption at rest remains in place.
- Build size / app performance unchanged.

## References

- `omni_runner/pubspec.yaml` (pin + warning block)
- `tools/audit/check-sqlcipher-eol.ts` (CI guard)
- `docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md` (operational playbooks)
- `docs/audit/findings/L11-07-sqlcipher-flutter-libs-0-7-0-eol-eol.md`
- `docs/POST_REFACTOR_SECURITY_AND_RELIABILITY.md` (C-03 PRAGMA key raw-hex)
- `docs/DECISIONS_LOG.md` §3 (SQLCipher raw-key PRAGMA format)
- `omni_runner/lib/core/secure_storage/db_secure_store.dart` (key store)
- `omni_runner/lib/data/datasources/drift_database.dart` (DB bootstrap)
- `.github/dependabot.yml` (`drift-and-storage` group silence)
