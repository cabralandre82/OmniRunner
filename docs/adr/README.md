# Architecture Decision Records (ADRs)

> One-file-per-decision log for architectural choices that are
> hard to reverse and that future contributors must be able to
> recover from the git log alone.

## Index

- [ADR-0001 — Provider fee ownership](./ADR-0001-provider-fee-ownership.md)
  — who absorbs Stripe/Asaas gateway fees (L09-08).

## Template

Copy [`./TEMPLATE.md`](./TEMPLATE.md) and rename it
`ADR-000X-<slug>.md` where `X` is the next sequential number.

## Status values

- **Proposed** — not yet accepted; discussion in a PR.
- **Accepted** — the current decision. Only one "Accepted" ADR per
  topic at a time.
- **Superseded by ADR-000Y** — kept for historical context; the
  newer ADR's implementation is authoritative.
- **Rejected** — decided against. Kept so future PRs don't
  re-propose the same path without reading why it was rejected.

## Cross-linking from code

When a migration / service / runbook implements an ADR decision,
add a comment pointing back to the ADR number. The CI guard
`audit:adr` verifies that every `Accepted` ADR is referenced by
at least one code / migration / runbook file.
