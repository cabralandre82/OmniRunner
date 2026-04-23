# Flutter / Dart SDK Pinning Runbook (L11-08)

> **Audience:** Mobile engineers, Release engineers, DevOps on-call.
> **Scope:** Keeping the Dart language spec used for local dev, CI,
> and release builds mechanically identical.
> **Related:** L11-06 (NPM dependency pinning — same philosophy, JS
> side), L11-07 (SQLCipher EOL — Flutter SDK bump is an exit
> criterion), L11-05 (secure storage policy), L01-30/31 (Android
> release hardening — ProGuard rules versioned alongside Flutter).

## 1. Why this matters

Dart has historically shipped minor-version releases that change the
language spec (null-safety rollout, sound-mode migration, records,
extension-type semantics). `pubspec.yaml` using a wide range like
`sdk: '>=3.8.0 <4.0.0'` lets:

- Dev A resolve against Dart 3.11 (Flutter 3.41).
- Dev B resolve against Dart 3.12 (Flutter 3.42) and get a different
  type-inference pass.
- CI resolve against Dart 3.11 but release build against a different
  Flutter version if a release workflow drifted (we hit this once —
  `release.yml` was on `flutter-version: 3.22.x` while `flutter.yml`
  was on `3.41.x`; silent divergence).

With a single-minor pin (`sdk: '>=3.11.0 <3.12.0'`, `flutter:
'>=3.41.0 <3.42.0'`):

- Local `flutter pub get` refuses to resolve on Flutter 3.42 without
  an intentional pubspec bump.
- CI uses the same minor across `flutter.yml`, `security.yml`,
  `release.yml`.
- Patch versions still float (`3.41.0`, `3.41.1`, … `3.41.9`) so we
  still inherit Dart SDK patches automatically.

## 2. What's in tree right now

| Artifact | Path | Purpose |
|----------|------|---------|
| Pubspec pins + warning block | `omni_runner/pubspec.yaml` (`environment.sdk` + `environment.flutter`) | Single-minor ranges, guarded by CI. |
| Repo-level toolchain pin | `.tool-versions` | asdf / fvm reads Flutter + Dart + Node majors so `cd <repo> && asdf install` gives the exact tools CI uses. |
| CI pin — analyze / test / build | `.github/workflows/flutter.yml` (3 jobs) | `flutter-version: '3.41.x'`. |
| CI pin — security scan | `.github/workflows/security.yml` | `flutter-version: '3.41.x'`. |
| CI pin — release build | `.github/workflows/release.yml` | `flutter-version: '3.41.x'` (previously drifted to 3.22.x pre-L11-08). |
| Runbook (this file) | `docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md` | Upgrade procedure + playbooks. |
| CI guard | `tools/audit/check-flutter-sdk-pinning.ts` (`npm run audit:flutter-sdk-pinning`) | Rejects any drift between the five pins above. |

## 3. The CI guard — `check-flutter-sdk-pinning.ts`

Enforced on every PR via `npm run audit:flutter-sdk-pinning`. It
verifies (all must pass):

1. `omni_runner/pubspec.yaml` declares BOTH `environment.sdk` and
   `environment.flutter` as **single-minor ranges** (upper bound is
   exactly `lower.minor + 1` at the same major with `.0` patch).
   Example OK: `>=3.11.0 <3.12.0`. Example FAIL: `>=3.8.0 <4.0.0`,
   `>=3.8.0 <3.13.0`, one-sided ranges, missing bounds.
2. A warning comment block ≥ 4 lines above `environment:` mentions
   L11-08 (keeps the edit-time signal visible).
3. `.tool-versions` contains `flutter <major>.<minor>.<patch>` AND
   `dart <major>.<minor>.<patch>` with minor matching the pubspec.
4. EVERY `flutter-version:` line in `.github/workflows/*.yml` uses
   the SAME minor as `environment.flutter`. No exceptions for
   "just this one job".
5. This runbook exists and references `check-flutter-sdk-pinning`
   (mutual linkage).

Exit `0` = clean. Exit `1` = at least one violation, each with a
locus and a concrete fix.

## 4. Upgrade procedure (when Flutter ships a new minor)

When Dart/Flutter ship a new minor we want to adopt (e.g., Flutter
3.42, Dart 3.12), perform ALL of the following in a SINGLE PR
titled `chore(flutter): bump to 3.42 (L11-08 sync)`:

1. **Pubspec** — `omni_runner/pubspec.yaml`:
   ```yaml
   environment:
     sdk: '>=3.12.0 <3.13.0'
     flutter: '>=3.42.0 <3.43.0'
   ```
   Keep the warning block intact.
2. **Tool-versions** — `.tool-versions`:
   ```
   flutter 3.42.<patch>
   dart 3.12.<patch>
   ```
3. **Workflows** — every `flutter-version:` line in
   `.github/workflows/*.yml` to `3.42.x`:
   - `flutter.yml` (3 jobs)
   - `security.yml`
   - `release.yml`
4. **Run the guard**: `npm run audit:flutter-sdk-pinning`. Must
   exit 0.
5. **Run full local quality gates**:
   - `cd omni_runner && flutter pub get` (expect clean).
   - `cd omni_runner && flutter analyze` (expect zero issues).
   - `cd omni_runner && flutter test` (expect all green).
   - `cd omni_runner && flutter build apk --release --debug`
     on the local machine (size + startup parity checks).
6. **Review Flutter release notes** — scan for:
   - Breaking Dart language changes (records semantics, patterns,
     extension types).
   - Breaking Android Gradle Plugin / Kotlin requirements (may
     cascade into L01-30/31 ProGuard rules).
   - Breaking package version constraints (may cascade into
     L11-06 `portal/package.json` if shared deps).
7. **PR description** — paste the `flutter --version` before/after,
   the guard output, and link the Flutter release notes.

## 5. Playbooks

### 5.1 CI fails `audit:flutter-sdk-pinning`

Root-cause the failure:

- **`sdk_range_too_wide`** / **`flutter_range_too_wide`** → someone
  widened the pubspec range. Restore the single-minor window. If
  they truly wanted a wider range, they need to explain WHY in PR
  description AND update this runbook — but widening is the exact
  anti-pattern L11-08 catches, push back hard.
- **`missing_warning_block`** → restore the `# L11-08 …` comment
  block above `environment:` (copy from git history).
- **`tool_versions_drift`** → `.tool-versions` doesn't match the
  pubspec minor. Bump or downgrade whichever is correct (usually
  pubspec is correct and `.tool-versions` is stale).
- **`workflow_flutter_drift`** → one or more workflows use a
  different `flutter-version:` minor than the pubspec. Align them
  all to the pubspec minor. If you INTENDED a different minor for
  one job, that's the L11-08 anti-pattern — fix the pubspec OR
  align the workflow.
- **`missing_runbook`** → someone deleted this file or renamed it;
  restore from git history.

### 5.2 A Flutter patch release lands (e.g., 3.41.2)

The pubspec range `>=3.41.0 <3.42.0` accepts all 3.41.x patches —
no pubspec change needed.

Optional: bump `.tool-versions` to `flutter 3.41.2` + review patch
release notes for regressions. The CI guard will stay green.

Do NOT widen the range to accommodate a patch — that's unnecessary.

### 5.3 A Flutter minor lands (e.g., 3.42) but we're not ready

Do nothing. The pubspec pin rejects 3.42 for all devs and CI. Any
dev who runs `flutter upgrade` locally and then `flutter pub get`
gets a clear error: "The current Flutter SDK version is 3.42.0.
Because … requires Flutter 3.41.x".

When we're ready, follow Section 4.

### 5.4 A Dart patch release lands (e.g., 3.11.3) with a CVE

1. Bump `.tool-versions` to the patched Dart/Flutter pair.
2. Re-run the guard — should stay green (minor range unchanged).
3. Workflows use `flutter-version: '3.41.x'` → `subosito/flutter-action`
   resolves to the latest 3.41.x patch automatically. On next CI
   run we inherit the patch.
4. Optional: bump the workflow pin to the exact patch
   (`flutter-version: '3.41.3'`) for deterministic CI. Only do
   this if the patch is security-critical.

### 5.5 `flutter_version_conflict` error in pub get

Symptom: `flutter pub get` fails with:
> The current Dart SDK version is 3.12.0.
> Because omni_runner requires SDK version `>=3.11.0 <3.12.0`, version solving failed.

Root cause: local dev machine has Flutter 3.42 installed, repo
pins 3.41. Fixes (in priority order):

1. **Preferred — asdf/fvm**: `cd <repo> && asdf install` (reads
   `.tool-versions`, installs exactly Flutter 3.41 alongside any
   other versions). Then `asdf shell flutter 3.41.1` or similar.
2. **Manual**: download Flutter 3.41.x from archive and `PATH` it.
3. **Never**: widen the pubspec range to accept both. That's the
   L11-08 anti-pattern and the CI guard rejects it.

### 5.6 Release build uses different Flutter than CI

This was the pre-L11-08 bug: `release.yml` used `flutter-version:
'3.22.x'` while `flutter.yml` used `3.41.x`. Symptoms:

- CI green, release APK crashes on device.
- Dart runtime behaviour differences (inlining, TFA, null-safety
  edge cases).
- Release-only build errors that CI never caught.

Fix: the CI guard now enforces that EVERY `flutter-version:` line
matches the pubspec minor. No workflow can slip through.

If this ever happens again, the `workflow_flutter_drift`
violation in the guard pinpoints the offending file + line.

### 5.7 An engineer asks "can I use Flutter 3.42 for this feature?"

Answer: no, unless they're doing the full upgrade (Section 4).
Flutter is a foundation layer — one contributor adopting a new
minor forces everyone else to upgrade locally AND CI. The single-
minor pin is the coordination mechanism.

If they have a strong reason, escalate: open a GitHub issue
tagged `flutter-sdk-bump` with the rationale. If accepted, the
work becomes the upgrade PR from Section 4.

## 6. Detection signals

| Signal | Source | Threshold | Action |
|--------|--------|-----------|--------|
| `audit:flutter-sdk-pinning` CI failure | CI | Any | 5.1 |
| Flutter release announcement | `flutter.dev/docs/release/release-notes` | New minor | Review release notes; decide if Section 4 is scheduled. |
| Dart CVE | GHSA for `dart-lang/sdk` | CVSS ≥ 7.0 | 5.4 + notify security on-call. |
| `flutter pub get` fails locally for devs | Developer Slack complaints | ≥ 2 in a week | Likely `.tool-versions` drift or dev hasn't run `asdf install`. Point at 5.5. |
| Release APK crashes on startup post-deploy | Sentry | Any | Check if a recent release workflow ran on a different Flutter than CI — 5.6. |

## 7. Rollback

If an upgrade (Section 4) breaks production:

1. Revert the upgrade PR chain (pubspec + .tool-versions +
   workflows + runbook if bumped).
2. The CI guard will fail on the revert commit only if any file
   was left inconsistent — inspect the guard output.
3. Run all quality gates on the reverted tree.
4. File a new finding L11-08-v2 with the crash signature + trigger
   + rollback commit — we don't want to retry blindly.

## 8. Cross-references

- **L11-06** — NPM dependency pinning. Same philosophy (exact
  pin + CI guard + runbook), but for NPM.
- **L11-07** — SQLCipher EOL. A Flutter major bump (3.x → 4.x) is
  an explicit exit criterion in ADR-009 because NDK deprecations
  force a migration away from the EOL plugin.
- **L11-05** — Secure storage policy. Uses `flutter_secure_storage`
  which is sensitive to Flutter/Dart spec changes (null-safety
  regressions in past minors).
- **L01-30 / L01-31** — Android release hardening. ProGuard rules
  and release signing expect specific Flutter gradle tooling;
  the single-minor pin keeps those rules stable.
- **L11-03 / L11-09** — gitleaks + least-privilege GITHUB_TOKEN.
  Pre-commit + workflow permissions surface. They share the same
  CI workflows; aligning `flutter-version:` across workflows
  keeps those guards effective.
