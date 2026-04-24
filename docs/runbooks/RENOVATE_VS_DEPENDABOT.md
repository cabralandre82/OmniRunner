# Renovate vs Dependabot — decision record (L11-11)

> **Status:** ratified · **Owner:** Platform · **Last updated:**
> 2026-04-21 · **Decision:** Stay on Dependabot; revisit in
> 2026 Q4

## Decision

Keep **Dependabot** as the single auto-update bot. Do NOT add
Renovate (no `renovate.json`). Re-evaluate at the end of
**2026 Q4**, gated on the trigger conditions in § Re-evaluation.

## Why we considered switching

The audit finding (L11-11) flagged that:

1. Renovate has **better grouping semantics** (regex + stable
   group names — "all eslint plugins" survives an `eslint-*`
   rename).
2. Renovate offers **lockfile maintenance** PRs that re-resolve
   transitive deps without bumping any direct dep.
3. Renovate can **auto-merge patches with a hard pin and a
   green CI** — Dependabot needs an extra workflow.

These are real ergonomic wins.

## Why we are staying on Dependabot

The current `.github/dependabot.yml` already neutralises the
biggest grouping pain (one PR per ecosystem instead of one
weekly mega-PR) — see the file for the 8 portal groups + 11
mobile groups + 3 CI groups, each with `applies-to:
version-updates` and a sibling `applies-to: security-updates`
catch-all.

The remaining Renovate-only wins are not worth the migration
cost at our scale, for these specific reasons:

| Renovate win                         | Status today                                                                  | Verdict                                 |
|--------------------------------------|--------------------------------------------------------------------------------|-----------------------------------------|
| Lockfile maintenance                 | We run `npm audit` + `npm ci --ignore-scripts` weekly via the existing CI.    | Adequate at this dependency volume.     |
| Auto-merge patch                     | Same outcome via `bors`-style automerge label + branch protection rule.       | Marginal; we still want human eyeball.  |
| Grouping by regex                    | Pattern globs in dependabot.yml cover the same cases.                         | Equivalent for our list.                |
| Best-effort scheduling               | Dependabot honours `timezone: America/Sao_Paulo` already.                     | Equivalent.                             |
| Commit-by-commit semver labels       | Dependabot adds `dependencies` + scope labels we already use.                 | Equivalent.                             |
| **Cross-repo orchestration**         | **N/A** — single mono-repo.                                                   | Renovate's headline feature is unused.  |
| **Custom datasources**               | **N/A** — we don't pin private artefact registries.                           | Unused.                                 |

The migration cost itself includes:

* Re-authoring the entire dependency-grouping config in
  Renovate's syntax — a one-shot but error-prone exercise (we
  have 22 groups across three ecosystems).
* Reviewing two months of duplicate PRs while we deprecate
  Dependabot.
* Operating a self-hosted Renovate (the GitHub-hosted version
  is rate-limited and we'd burn the free quota inside a week
  given our schedule).
* Updating every internal runbook that references Dependabot's
  PR shape (reviewer assignment, label triage).

That cost is non-trivial and the marginal benefit at our scale
is small.

## Re-evaluation triggers

We **will** revisit the decision when any of the following
becomes true:

1. **Repo count > 1** — when we factor `omni-shared-types` or a
   white-label repo out of the mono-repo, Renovate's cross-repo
   orchestration becomes a real value.
2. **Dependabot grouping breaks** — if a future Dependabot
   release narrows the `groups:` semantics (the feature is
   technically still GA-but-evolving).
3. **Auto-merge becomes a bottleneck** — if engineering hours
   spent shepherding patch PRs > 2 h/week sustained for two
   months. Tracked via a manual quarterly tally.
4. **Lockfile drift** — if `audit:lockfile-drift` (L11-13)
   flags > 5 drifts/quarter, we want Renovate's lockfile
   maintenance.

If none of those triggers fire by 2026-Q4, we re-ratify
Dependabot for another year.

## How to add a new dependency group (today)

Edit `.github/dependabot.yml` and follow the existing pattern:

```yaml
groups:
  <semantic-name>:
    applies-to: version-updates
    patterns:
      - "<glob>"
    update-types: ["minor", "patch"]
```

Avoid groups that span ecosystems — Dependabot's `groups:` is
scoped to one `package-ecosystem` block.

## Cross-references

* `.github/dependabot.yml` — current grouping configuration
* `docs/audit/findings/L11-04-dependabot-um-pr-mensal.md` —
  original grouping fix (committed)
* `docs/audit/findings/L11-13-lockfile-drift.md` — CI guard
* `tools/audit/check-actions-pinned.ts` — supply-chain CI guard
