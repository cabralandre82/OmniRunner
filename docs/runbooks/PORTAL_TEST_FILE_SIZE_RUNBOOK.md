# Portal test-file size runbook (L17-04)

> **Scope:** Next.js portal (`portal/src/**`) Vitest suites
> **Owner:** portal
> **Last updated:** 2026-04-21
> **Related findings:** `L17-04`, `L17-01` (financial routes must-use
> `withErrorHandler`), `L17-03` (`withErrorHandler` typing).

## 1. Why this exists

Mega-test-suites are a failure mode of test-as-contract: when a single
`*.test.ts` grows past ~400 lines and covers 4+ orthogonal concerns
under one shared fixture, three things happen:

1. Any diff that flips an unrelated assertion forces Vitest to
   re-evaluate the entire file, so pre-commit runs get noticeably
   slower.
2. When a test breaks, the author is tempted to comment out the failing
   `it(...)` block ("I'll come back to this") because walking the 800-
   line context takes longer than the fix itself. We have the git
   history to prove it.
3. Shared mutable mock state + 4 describe-blocks = 1 cross-describe
   leak waiting to happen. Flaky tests follow.

Historical offender: `portal/src/lib/qa-e2e.test.ts` (842 lines, 24
tests, 4 describes, ~370 lines of shared mock-DB fixtures at the top).
This runbook documents the invariant that replaced it.

## 2. Invariant

**No portal `*.test.ts` file may exceed 800 lines (hard cap). New
files should target < 400 lines (soft cap).**

- **Hard cap (800 lines)** — trips the CI guard
  `npm run audit:portal-test-file-size`. A fail here must be resolved
  by splitting before merge. No allowlist.
- **Soft cap (400 lines)** — emits a warning. Triage policy: split on
  your next touch, or add the file to `ALLOWLIST` in
  `tools/audit/check-portal-test-file-size.ts` with a code review. The
  allowlist today covers 9 files that legitimately exercise many
  payload shapes (webhook route tests, money/schemas, partnerships,
  swap / coins.reverse / custody webhook, csrf).
- **Shared fixtures** live under `portal/src/lib/__qa__/` (or the
  feature-local `__tests__/` folder). Fixture modules do NOT count
  against the test cap — they are the "extract method" end of the
  split.

## 3. What shipped (L17-04)

| Piece                                           | File                                                         |
| ----------------------------------------------- | ------------------------------------------------------------ |
| Shared mock-DB + RPC dispatcher + token helpers | `portal/src/lib/__qa__/qa-e2e-fixtures.ts` (402 lines)       |
| Smoke-test describe (section 1, 8 tests)        | `portal/src/lib/qa-e2e-smoke.test.ts` (194 lines)            |
| Idempotency describe (section 2, 4 tests)       | `portal/src/lib/qa-e2e-idempotency.test.ts` (137 lines)      |
| Anti-fraud describe (section 3, 8 tests)        | `portal/src/lib/qa-e2e-antifraud.test.ts` (174 lines)        |
| Concurrency describe (section 4, 4 tests)       | `portal/src/lib/qa-e2e-concurrency.test.ts` (172 lines)      |
| CI guard                                        | `tools/audit/check-portal-test-file-size.ts`                 |
| This runbook                                    | `docs/runbooks/PORTAL_TEST_FILE_SIZE_RUNBOOK.md`             |

All 24 tests continue to pass after the split (same assertions, same
mock behaviour). The monolithic `qa-e2e.test.ts` was deleted.

## 4. How to write a new suite

### 4.1 Single concern, < 400 lines

Happy path. Keep the test file in `portal/src/lib/` next to the module
under test, named `foo.test.ts`.

### 4.2 Multiple concerns sharing setup

If your module has 3+ top-level `describe`s and the setup is non-
trivial (mock DB, fetch stubs, fixture builders), do this:

1. Create `portal/src/lib/__<feature>__/<feature>-fixtures.ts` with:
   - Types for the mock domain objects.
   - A single `state` object exported as mutable (so both fixture
     helpers and test assertions read/write the same reference).
   - `resetState()` + any sub-reset (`resetIntents()`, `resetLedger()`,
     …).
   - Pure dispatch functions (`handleRpc(name, params)`) that mutate
     `state`.
   - A shared `vi.fn()` (`export const mockRpc = vi.fn()...`) and a
     `rewire<X>()` helper that resets its implementation.
   - Any `makeFromMock(table)` style chainable stubs.
2. Split the suite into `<feature>-<concern>.test.ts` files. Each file
   MUST include at its top:
   ```ts
   vi.mock("@/lib/supabase/service", () => ({
     createServiceClient: () => ({
       from: (t: string) => makeFromMock(t),
       rpc: (...a: unknown[]) => (mockRpc as ...)(...a),
     }),
   }));
   ```
   The `vi.mock` factory is hoisted per-test-file by the Vitest plugin
   — you **cannot** extract it into the fixtures module.
3. Each test file calls `resetState()` + `resetIntents()` +
   `rewireMockRpc()` in its `beforeEach`.
4. Run `npm run audit:portal-test-file-size` locally — it must stay
   green.

### 4.3 A single describe legitimately > 400 lines

First effort: split by sub-describe (smoke vs. edge-cases vs. error
paths). If it really is one concern — e.g. the 30-gateway-payload
custody webhook test — add the file path to `ALLOWLIST` in
`tools/audit/check-portal-test-file-size.ts` with a short rationale in
the commit message.

## 5. Detection signals

| Signal                                                 | Surface                                                                                     |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| CI                                                     | `npm run audit:portal-test-file-size` (hard cap 800 + required splits + forbidden monolith) |
| Local                                                  | `wc -l portal/src/**/*.test.ts | sort -n | tail`                                             |
| Vitest                                                 | `npx vitest run` — any duration regression > 20% against main should prompt a look         |
| PR review                                              | New test files > 400 lines trigger a "can this split?" comment                              |

## 6. Operational playbooks

### 6.1 CI fails with `[FAIL] <file>.test.ts (842 lines)`

1. `grep -n "^describe" <file>.test.ts` — identify the top-level
   describes.
2. Extract the shared setup (mocks, fixtures) into
   `src/lib/__<feature>__/<feature>-fixtures.ts`.
3. Create one test file per describe, importing from the fixtures
   module.
4. Delete the monolithic file.
5. Re-run `npm run audit:portal-test-file-size` locally.

### 6.2 `[FAIL] missing expected split file: qa-e2e-...`

Someone (or a merge conflict) accidentally deleted one of the 4
`qa-e2e-*.test.ts` files or the fixtures module. Restore from git or
re-create from the template in this runbook.

### 6.3 `[FAIL] the monolithic qa-e2e.test.ts is back`

Same root cause — a merge reintroduced the deleted file. Resolve by
keeping HEAD's split and dropping the monolith.

### 6.4 A new file legitimately exceeds the soft cap

1. Attempt a split first (use the §4.2 pattern).
2. If the file is cohesive around a single concern (many input
   payloads of one route), add the relative path to `ALLOWLIST` in
   `tools/audit/check-portal-test-file-size.ts` and explain in the PR.

### 6.5 Test runtime regresses after split

Each test file has its own hoisted `vi.mock` factory, so mock setup
runs 4× instead of 1×. If the setup cost dominates, hoist heavy
initialisation into the fixtures module and do per-file caching (e.g.
`let cached; export function getX() { return cached ??= buildX(); }`).
Do NOT go back to a monolithic file.

## 7. Rollback posture

The split is a pure refactor — zero production runtime impact. Rollback
would mean reintroducing the 842-line monolith and violating the CI
guard. Only justified if a future Vitest breakage requires it (none
seen to date).

## 8. Invariants (enforced by CI)

- `portal/src/**` has NO `*.test.ts` file > 800 lines (hard cap).
- `portal/src/lib/qa-e2e-smoke.test.ts`,
  `qa-e2e-idempotency.test.ts`, `qa-e2e-antifraud.test.ts`,
  `qa-e2e-concurrency.test.ts` and `__qa__/qa-e2e-fixtures.ts` all
  exist.
- `portal/src/lib/qa-e2e.test.ts` does NOT exist.
- Soft-cap warnings (> 400 lines, non-allowlisted) are visible in the
  CI output so PR reviewers can escalate.

## 9. Cross-references

- `L17-01` — financial routes must-use `withErrorHandler` (separate
  CI guard `tools/check_financial_routes_have_error_handler.ts`).
- `L17-03` — `withErrorHandler` typing: preserves handler tuple
  signature, so newly split tests can still declare typed `ctx`.
- `L17-05` — logger Sentry capture: split tests still share the
  `mockCaptureException/Message` contract.
