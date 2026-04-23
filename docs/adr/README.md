# Architecture Decision Records (ADRs)

> One-file-per-decision log for architectural choices that are
> hard to reverse and that future contributors must be able to
> recover from the git log alone.

## Index (ordered chronologically)

| # | Title | Status | Audit ref |
|---|---|---|---|
| ADR-001 | [Flutter Clean Architecture](./001-flutter-clean-architecture.md) | Accepted | L18-04 |
| ADR-002 | [Portal — Next.js App Router](./002-portal-next-app-router.md) | Accepted | L17 |
| ADR-003 | [Feature flags via Supabase](./003-feature-flags-supabase.md) | Accepted | L08 |
| ADR-004 | [i18n strategy](./004-i18n-strategy.md) | Accepted | L07-01 |
| ADR-005 | [Observability stack](./005-observability-stack.md) | Accepted | L20 |
| ADR-006 | [Testing strategy](./006-testing-strategy.md) | Accepted | L17 |
| ADR-007 | [Custody / clearing model](./007-custody-clearing-model.md) | Accepted | L03 |
| ADR-008 | [Swap as off-platform credit cession](./008-swap-as-off-platform-credit-cession.md) | Accepted | L09-05 |
| ADR-009 | [SQLCipher EOL migration](./009-sqlcipher-eol-migration.md) | Accepted | L01-32, L01-33 |
| ADR-0001 | [Provider fee ownership](./ADR-0001-provider-fee-ownership.md) | Accepted | L09-08 |

> **Naming convention.** New ADRs MUST use the form
> `ADR-NNNN-<slug>.md` with 4-digit zero-padded number. Legacy
> ADRs (001–009 with 3-digit prefix and no `ADR-` token) are kept
> for historical fidelity but **never** rename them — git history
> would break. The CI guard `audit:adr` enumerates BOTH styles.

## Template

Copy [`./TEMPLATE.md`](./TEMPLATE.md) and rename it
`ADR-NNNN-<slug>.md` where `NNNN` is the next sequential number.

## Status values

- **Proposed** — not yet accepted; discussion in a PR.
- **Accepted** — the current decision. Only one "Accepted" ADR per
  topic at a time.
- **Superseded by ADR-NNNN** — kept for historical context; the
  newer ADR's implementation is authoritative.
- **Rejected** — decided against. Kept so future PRs don't
  re-propose the same path without reading why it was rejected.

## When to write an ADR

Write an ADR when the decision is:

1. **Hard to reverse** — schema choices, framework choices,
   security boundaries.
2. **Cross-team** — affects more than one squad's ability to ship.
3. **Compliance-relevant** — touches LGPD/BCB/COAF/Strava ToS.
4. **Surface area for future debate** — anything where 6 months
   from now someone will ask "why did we do it this way?"

Do **not** write an ADR for:

- Day-to-day refactors with no new constraint.
- Library upgrades that follow the existing stack.
- Bugfixes (use commit message + finding doc).

## Cross-linking from code

When a migration / service / runbook implements an ADR decision,
add a comment pointing back to the ADR number. The CI guard
`audit:adr` verifies that every `Accepted` ADR is referenced by
at least one code / migration / runbook file, AND that every ADR
file is listed in the index above.

## Audit ref

This README is the canonical answer to L17-07 — "docs/adr/ ativo
para decisões arquiteturais". CI guard
`audit:adr-governance` validates the index and naming
conventions.
