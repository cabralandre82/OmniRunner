# NPM DEPENDENCY PINNING RUNBOOK — L11-06

> **Audit refs:** L11-06 · [`docs/audit/findings/L11-06-dependencias-com-permitem-breaking-minor.md`](../audit/findings/L11-06-dependencias-com-permitem-breaking-minor.md) · anchor `[11.6]` in [`docs/audit/parts/05-cro-cso-supply-cron.md`](../audit/parts/05-cro-cso-supply-cron.md)
> **Status:** fixed (2026-04-21)
> **Owner:** platform
> **Related:** L11-05 (secure storage policy), L11-07 (sqlcipher EOL), L11-08 (Flutter SDK pinning), L11-01/02/03/04/09 (supply-chain sextet — existing Onda 0 coverage)

---

## 1. Why this exists

Before this PR, `portal/package.json` shipped `"next": "^14.2.15"` and `"zod": "^4.3.6"`. Both carets are reconciled by npm as "any 14.x" / "any 4.x" on every `npm install` — the exact version shipped to users was whatever npm felt like at the moment of the last `npm ci` run on the build machine.

Real-world bite we have already felt in this codebase (not hypothetical):

- `next ^14.2.15` already resolved to `14.2.35` on the current CI image. That is 20 patch-bumps of silently-changed middleware ordering, image-optimiser rewrites, and dev-mode cookie behaviour between what a new clone downloads and what the last reviewer tested against.
- `zod` spans the 3→4 type-break. A caret on `^3.x` could, across a poorly-reviewed PR that bumps `@asteasolutions/zod-to-openapi` to its 4-compatible line, cascade into a `zod@4` auto-install whose strictness rules reject inputs that the old validator accepted — silently tightening API contracts without a deploy.
- `@supabase/ssr` bumped cookie names from `sb-<project>-auth-token` to shorter alternatives in a past minor; a caret-driven bump would have invalidated every logged-in session without a deploy note.
- `@sentry/nextjs` has shipped breaking changes to `getActiveSpan()` in minor releases — our logger helper (L17-05) depends on that exact contract.

The fix is a **two-layer defence**:

1. **`.npmrc` files** — prevent casual `npm install foo` from writing a caret to package.json.
2. **CI guard** — refuse any PR that hand-edits package.json to reintroduce a caret on a critical boundary, or slips a `*` / `latest` tag anywhere.

---

## 2. Policy matrix

| Package | Why critical | Pinning rule |
|---|---|---|
| `next` (portal) | rendering / routing / middleware boundary; silently changes redirect + cookie semantics across patches | EXACT |
| `@supabase/ssr` (portal) | auth cookie contract; minor bumps have changed cookie names | EXACT |
| `@supabase/supabase-js` (portal) | RPC + RLS error shape contract | EXACT |
| `zod` (portal) | schema contract; typing rules across 3↔4 are breaking | EXACT |
| `@sentry/nextjs` (portal) | observability boundary; `getActiveSpan` semantics | EXACT |
| `tsx` (root) | entrypoint for every `npm run audit:*` script | EXACT |
| `lefthook` (root) | pre-commit runner; controls `flutter-analyze`, `portal-lint`, `gitleaks` invocation | EXACT |
| `js-yaml` (root) | audit registry parser; semantic changes across versions shift yaml behaviour | EXACT |
| everything else | leaf or transitive — caret is acceptable | caret OK, but banned `*` / `latest` |

If you need to add or remove a package from CRITICAL_PACKAGES:

1. Justify in the PR description, citing the contract the package owns.
2. Edit `tools/audit/check-npm-dependency-pinning.ts::CRITICAL_PACKAGES`.
3. Update this runbook's matrix above in the same PR.
4. Ensure `npm run audit:npm-dependency-pinning` stays green.

---

## 3. What the fix ships

### 3.1 Files

| Path | What |
|---|---|
| `.npmrc` | workspace-root npmrc: `save-exact=true`, `save-prefix=`, `engine-strict=true` |
| `portal/.npmrc` | portal-scope npmrc: same three lines |
| `package.json` (root) | `tsx`, `lefthook`, `js-yaml` pinned to exact |
| `portal/package.json` | `next`, `@supabase/ssr`, `@supabase/supabase-js`, `zod`, `@sentry/nextjs` pinned to exact |
| `tools/audit/check-npm-dependency-pinning.ts` | CI guard; three subchecks (npmrc presence + shape, criticals exact, no banned specifiers anywhere) |

### 3.2 CI guard — what it does

`npm run audit:npm-dependency-pinning` runs three sub-checks:

1. **npmrc** — asserts both `.npmrc` and `portal/.npmrc` exist AND contain `save-exact=true` + `save-prefix=` lines. If either file is missing OR one of the lines is removed, CI fails.

2. **criticals** — for each entry in `CRITICAL_PACKAGES`, loads the manifest and checks the version range against `isExactVersion()`:
   - Rejects leading `^` / `~`.
   - Rejects `>=` / `<=` / `>` / `<` ranges.
   - Rejects `1.0.0 - 2.0.0` hyphen ranges.
   - Rejects `||` OR ranges.
   - Rejects `*` / `x` placeholders.
   - Rejects `file:`, `link:`, `git*`, `https?:`, `github:`, `npm:` aliases, `workspace:` protocols.
   - Accepts: plain semver (`1.2.3`), prerelease (`1.2.3-beta.0`), build metadata (`1.2.3+build.42`).

3. **specifiers** — scans ALL deps (not just criticals) for `*`, `latest`, `x`. These are banned everywhere — they make `npm install` nondeterministic. Hyphen ranges and `>=` are *allowed* on leaf packages because a) they already exist in the tree and b) moving them all to exact pins would be a full lockdown that blocks routine maintenance. We tighten boundary-package exactness first; full lockdown is a follow-up (L11-06-extended if we decide to ship it).

---

## 4. Playbooks

### 4.1 A security advisory says: upgrade `next`

Do **not** bump inside a caret and hope. Do:

```bash
# 1. Read the advisory. Note the minimum fixed version.
# 2. Update the exact pin in portal/package.json.
cd portal
npm install next@14.2.40 --save-exact
# (save-exact is already the default via .npmrc, but the explicit flag
#  documents intent for the diff reader.)

# 3. Run the guard locally.
npm run -w .. audit:npm-dependency-pinning

# 4. Run the full portal test suite + e2e smoke.
npm run test
npm run test:e2e

# 5. Ship the PR WITH the advisory link in the description.
```

The guard will fail if the install accidentally brings a caret back — that means either `.npmrc` was deleted or the peer-dep requires an unpinned version (rare for `next`, happens with `react` in some plugin ecosystems). Don't paper over it — fix the root cause.

### 4.2 `npm install foo` accidentally reintroduced a caret

`.npmrc` should make this impossible, but it can happen if:

- The contributor is on a machine where npm 9+ ignores `.npmrc` (rare — only happens with malformed config).
- The command was run from the wrong directory (root → resolves the root `.npmrc`, NOT `portal/.npmrc` → if `portal/` ever runs `npm install foo` from its parent, the scope mismatches).
- Someone edited package.json by hand.

The guard catches it. Fix:

```bash
cd portal
npm install <pkg>@<exact> --save-exact
# Then verify the result:
npm run -w .. audit:npm-dependency-pinning
```

### 4.3 `audit:npm-dependency-pinning` fails on a legitimate caret

If the reviewer decides a critical package SHOULD be allowed caret ranges (almost never — but imagine `react` which is peer-dep gated and benefits from caret compat), the change is a deliberate removal:

1. Remove the package from `CRITICAL_PACKAGES` in `tools/audit/check-npm-dependency-pinning.ts`.
2. Update §2 Policy Matrix above with the justification.
3. Both edits in the SAME commit.
4. PR requires a code-owner review who understands the supply-chain lens.

Do **not** loosen the guard to "allow caret on critical" — that defeats the entire point.

### 4.4 Dependabot / Renovate auto-PRs

When the bot opens a PR to bump `next` from `14.2.35` to `14.2.40`:

- It should edit only the exact version string.
- The guard should stay green.
- If the guard fails, the bot's PR template generated a caret — disable that in the bot config, or convert manually.

### 4.5 `*` / `latest` snuck in via a newly-added dep

`sonner: "latest"` is a common copy-paste mistake. The guard catches it. Fix:

```bash
cd portal
npm install sonner@<exact> --save-exact
```

And add a PR-review checklist item: "no `latest` / `*` in package.json".

### 4.6 The `npm ci` output looks different on two machines

Symptom: developer A runs `npm ci` and gets `next@14.2.35`; developer B gets `14.2.40`. With caret pins this was expected. With exact pins it means:

1. `package-lock.json` is out of sync with `package.json` — re-generate on the machine that sees the drift:
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   ```
   Then commit the new lockfile.

2. Or developer B is on a fork / branch that updated package.json but didn't commit package-lock.json. The guard only checks manifests, not lockfiles — a follow-up (L11-06-ext) could add lockfile drift detection, but is out of scope here.

---

## 5. Detection signals

| Signal | Source | Action |
|---|---|---|
| `audit:npm-dependency-pinning` red in CI | `npm run audit:npm-dependency-pinning` | §4.2 or §4.3 |
| `npm install foo` silently adds `^foo` to package.json | local dev | re-install with `--save-exact`, verify `.npmrc` still has `save-exact=true` |
| `next` / `zod` / `@supabase/*` version in `node_modules` differs from `package.json` | `npm ls <pkg>` vs manifest | stale lockfile — `npm ci` or `rm -rf node_modules && npm install` |
| CVE advisory lands against a critical package | Dependabot / `npm audit` | §4.1 |
| Bot PR re-introduces `^` | Dependabot / Renovate | disable caret in bot config, re-open PR with exact |

---

## 6. Cross-refs

- **L11-05** — Secure storage policy; shares the same supply-chain lens. Heuristics there are code-side (SharedPreferences vs SecureStorage); here they are manifest-side (caret vs exact).
- **L11-07** — `sqlcipher_flutter_libs: ^0.7.0+eol`. The EOL tag means npm/pub won't ship patches even if a CVE lands. Pinning is pointless without a maintained upstream — that fix is a dependency REPLACEMENT, not a pinning change.
- **L11-08** — Flutter SDK pinning via `environment.sdk: '>=3.8.0 <4.0.0'`. The Dart-side analogue of this runbook; same rationale, different toolchain.
- **L11-01/02/03/04/09** — already shipped via the Onda-0 supply-chain sextet (CVE scanning, SBOM, provenance, reproducibility). This runbook is the missing link between those checks and the dev-experience of `npm install`.
- **L17-05** — Logger / Sentry captures depend on `@sentry/nextjs.getActiveSpan()`. If that contract ever changes behind a caret bump, L17-05 tests would go red silently. Pinning `@sentry/nextjs` here closes that gap.
