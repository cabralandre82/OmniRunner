# Shared Types — TS ↔ Dart Codegen Strategy

**Status:** Ratified (2026-04-21), implementation deferred.
**Owner:** platform
**Related:** L17-09, L14-01 (OpenAPI registry), L08-09 (event
catalog), L17-08 (monorepo tooling decision).

## The drift problem

`portal/src/lib/schemas.ts` defines Zod schemas for API
request/response shapes. `omni_runner/lib/domain/entities/*.dart`
defines `freezed` data classes for the same shapes. Today they
are kept in sync by **convention + code review**, which has
produced two real bugs in the past quarter (one missing field
on a Zod schema; one Dart class accepting `null` where the
server returns `0`).

## Decision

**OpenAPI as single source of truth**, generated **from** the
running portal, consumed **by** both portal and mobile codegen
on CI.

```
                     portal/src/lib/openapi/registry.ts
                     (Zod → OpenAPI 3.1 emitter, L14-01)
                                  │
                                  ▼
                          openapi.v1.json
                                  │
                  ┌───────────────┴───────────────┐
                  ▼                               ▼
       portal codegen                       mobile codegen
       @hey-api/openapi-ts                  openapi_generator
       → portal/src/lib/api-client/         → omni_runner/lib/api/generated/
       (Zod schemas + typed fetch)         (freezed + json_serializable)
```

The portal owns the **emitter** (Zod is the canonical authoring
surface — it gives runtime validation for free); the mobile
side is a pure **consumer**.

## Why not "Dart-first" or "shared package"

We considered three alternatives and rejected each:

1. **`packages/shared-contracts/` with TypeScript as source.**
   Would force `omni_runner` to consume TS at build time,
   pulling in npm + tsx + Node into the Flutter pipeline. We
   already rejected pnpm-workspaces / Turborepo for this exact
   reason (L17-08). OpenAPI as the wire contract is
   tooling-neutral — both sides only need an HTTP-spec parser.
2. **Dart-first using `built_value` schemas.** Reverse of the
   above; would force the portal to consume Dart-emitted JSON
   schema. Loses Zod's runtime validation in the API layer
   (which we leverage for `400 VALIDATION_FAILED` responses).
3. **Hand-authored OpenAPI YAML in `docs/api/openapi.yaml`.**
   Drift between the YAML and the actual portal handlers is
   guaranteed within a quarter. Same failure mode as the
   current Zod / Dart drift, just relocated.

## Migration plan (deferred to Wave 3)

| Phase | Scope | When |
|-------|-------|------|
| 0     | This decision ratified (L17-09 closed as `correction_type: docs`) | 2026-04-21 |
| 1     | All Zod schemas in `portal/src/lib/schemas.ts` registered in `portal/src/lib/openapi/registry.ts` (today: ~ 60% covered, the rest are private admin shapes) | 2026-Q3 |
| 2     | CI step that runs `npx @hey-api/openapi-ts` against the published OpenAPI doc and asserts `portal/src/lib/api-client/` is up to date (commit-blocking) | 2026-Q3 |
| 3     | `omni_runner/lib/api/generated/` produced by `openapi_generator` in `flutter pub run build_runner build`. Hand-written `lib/domain/entities/*.dart` migrated module-by-module to import from `generated/` | 2026-Q4 |
| 4     | Hand-authoring `lib/domain/entities/*.dart` becomes a CI failure (`audit:no-handwritten-dto`) for any class whose name appears in the OpenAPI doc | 2027-Q1 |

## Why not in this batch

This is a 6-figure-LOC migration touching every screen on
mobile and a substantial chunk of the portal. It needs:

- A spike to confirm `openapi_generator` produces idiomatic
  Dart for our nullable / discriminated-union patterns.
- A staged rollout — module-by-module, with the freezed →
  generated swap carefully reviewed.
- Coordination with the mobile release cadence (the spec
  bumps would need to ship in lockstep).

A single PR cannot do this responsibly, so we close L17-09 by
ratifying the **direction** in this runbook and tracking the
phased work in the Wave-3 backlog.

## Interim mitigation (in production today)

- L14-01: OpenAPI registry exists and is the contract for
  publicly-documented routes.
- L08-09: event catalog has a CI guard
  (`tools/audit/check-event-catalog.ts`) that blocks drift
  between TS and Dart for the analytics surface specifically.
- Code review: PRs that touch a Zod schema must explicitly
  call out the matching Dart change (or note "internal only")
  in the PR description. This is a soft control; the codegen
  above is the hard one.

## See also

- `portal/src/lib/openapi/registry.ts` (L14-01)
- `docs/runbooks/MONOREPO_TOOLING_DECISION.md` (L17-08)
- `docs/analytics/EVENT_CATALOG.md` (L08-09)
