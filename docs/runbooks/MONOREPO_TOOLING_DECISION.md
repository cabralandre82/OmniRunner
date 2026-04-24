# Monorepo tooling decision (L17-08)

> **Status:** ratified · **Owner:** Platform · **Last updated:** 2026-04-21
> **Decision:** Stay on the current dual-package layout
> (`portal/` + `omni_runner/`); revisit when **package count
> ≥ 3**.

## Decision

Do NOT adopt Turborepo, Nx, or pnpm-workspaces today.
Continue with the current layout:

* `portal/` — Next.js + npm workspace.
* `omni_runner/` — Flutter + pub workspace.
* root `package.json` for repo-wide audit / lint scripts.

Re-evaluate when ANY of the following becomes true:

1. We factor `omni-shared-types` (TS + Dart code-gen, sourced
   from a single `events.proto` / Zod schema) into its own
   package — this immediately makes 3 packages and Turborepo's
   value-prop (cache + dependency-graph-aware test runs)
   becomes real.
2. A white-label tenant repo appears (e.g.
   `partner-runforhealth-portal/`) and we want to share the
   custody UI components.
3. CI test time on `portal/` exceeds **8 minutes** sustained
   over a sprint — Turborepo's remote cache could shave that
   meaningfully.

## Why we are NOT adopting Turborepo today

| Turborepo win                       | Status today                                                                                                                  | Verdict                              |
|-------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|--------------------------------------|
| Dependency-graph-aware task running | We have **two** packages and they share zero JS code (Dart + TS); the graph is trivially `[portal] [omni_runner]`.            | No win.                              |
| Remote cache                         | CI total wall time ~5 min for portal + ~7 min for mobile. Cache hit-rate would be ~30% pre-warm. Marginal.                  | Not worth migration.                 |
| Filtered task running               | `npm run test --workspace portal` already does what we need.                                                                  | Native npm covers it.                |
| Pipeline composition                | We have ~120 `audit:*` scripts. They are independent — running them in serial vs parallel is an 8 s difference.            | Marginal.                            |
| Versioning + changesets             | Single-versioned monorepo (we don't publish to npm).                                                                         | N/A.                                 |

## Why we are NOT adopting Nx today

Nx is heavier than Turborepo and aimed at much larger graphs
(20+ packages). We are an order of magnitude smaller. The
generator scaffolding + plugin ecosystem — the parts that
justify Nx in big organisations — would be pure overhead at
our scale.

## Why we are NOT adopting pnpm-workspaces today

The Flutter side already lives in a separate `pub` workspace;
unifying the JS side under pnpm-workspaces would NOT cover the
mobile package. We get partial benefit only.

Additionally, our Dependabot grouping (L11-04) is
ecosystem-keyed; switching from npm to pnpm at this point
would force a re-validation of every PR-shape automation in
the existing `.github/dependabot.yml`.

## What we ARE doing in the meantime

The current dual-package layout has friction; we mitigate
without adopting a tool:

1. **Top-level audit registry.** All audit scripts live in
   the root `package.json` as `audit:*` entries (today: ~120).
   The agent + on-call can run `npm run audit:k4-security-fixes`
   without `cd`'ing into `portal/`.
2. **Single CI workflow per concern.** `.github/workflows/`
   has separate jobs for portal-test, mobile-test,
   audit-scripts, and linting. Each runs in its own runner
   so they parallelise without orchestration tooling.
3. **Shared types via copy-and-CI-guard.** When we need to
   share an enum (e.g. PRODUCT_EVENT_NAMES → Dart →
   `event_domain`), we copy by hand and add a CI guard
   that fails on drift (see
   `tools/test_l08_01_02_product_events_hardening.ts`,
   `tools/audit/check-event-catalog.ts`). This is the
   correct trade-off until shared-types ≥ 3 or copy points ≥ 5.
4. **Top-level `package-lock.json` policing.** The
   `audit:lockfile-drift` CI guard (L11-13) ensures the root
   and `portal/` lockfiles agree on shared dependencies.

## Migration path when triggers fire

When the re-evaluation triggers fire, the migration to
Turborepo would proceed as follows:

1. Add `turbo` as a dev dependency at the repo root.
2. Author `turbo.json` pipelines for `build`, `test`, `lint`,
   `audit` with explicit `dependsOn` graphs.
3. Migrate root `package.json` `scripts` to forward to
   `turbo run <task>`.
4. Wire the Vercel remote cache (free for our team size).
5. Smoke test against an `audit:*` matrix run.
6. Cut over CI workflows to use `turbo run` instead of
   `npm run --workspace`.

Estimated effort: **2-3 dev-days** + 1 sprint of monitoring.
The migration is reversible (delete `turbo.json`, restore
`scripts`).

## Cross-references

* `docs/audit/findings/L17-08-ausencia-de-monorepo-tooling-turbo-nx-pnpm-workspaces.md`
* `docs/audit/findings/L11-04-dependabot-um-pr-mensal.md`
* `docs/audit/findings/L11-13-lockfile-drift.md`
* `docs/audit/findings/L17-09-sem-shared-types-ts-dart-entre-portal-e-mobile.md`
  (sibling: shared-types is a stronger trigger than
  monorepo-tooling)
