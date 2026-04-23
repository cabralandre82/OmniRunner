# `withErrorHandler` typing runbook (L17-03)

> **Scope:** Next.js portal (`portal/src/lib/api-handler.ts`)
> **Owner:** portal
> **Last updated:** 2026-04-21
> **Related findings:** `L17-03`, `L17-01` (financial-routes must-use
> wrapper), `L17-05` (logger Sentry capture), `L13-06` (request_id
> propagation).

## 1. Why this exists

`withErrorHandler(handler, routeName, options?)` is the outermost
safety-net for every App-Router handler in `portal/src/app/api/**` and
is **must-use** for financial routes (see
`tools/check_financial_routes_have_error_handler.ts`). It:

1. Wraps throws into the canonical `{ ok:false, error:{...} }` 500
   envelope (L14-05).
2. Propagates `x-request-id` (L13-06) on success and on error.
3. Routes every uncaught error through `logger.error` → Sentry
   (L17-05).
4. Tags the active Sentry span with `omni.route` + `http.method`.
5. Accepts an opt-in `errorMap` for domain errors.

Historically, the wrapper signature was

```ts
export function withErrorHandler<
  H extends (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
>(handler: H, ...): H
```

The `routeArgs: any[]` escape hatch silently erased the
dynamic-route context type. Inside `/api/platform/custody/[groupId]/daily-cap/route.ts`
a handler typed `ctx: { params: { groupId: string } }` compiled fine
when someone accessed `ctx.params.slug` — the mistake surfaced only at
runtime as a 500 when `params.slug` came back `undefined`. Same risk on
the nested routes `[planId]/weeks/[weekId]/*` where 5 params are in
play.

This runbook documents the new invariant that closes that gap.

## 2. Invariant

**`withErrorHandler` preserves the wrapped handler's signature
**end-to-end**, driven by a tuple generic `TArgs extends readonly
unknown[]`.**

```ts
export function withErrorHandler<TArgs extends readonly unknown[]>(
  handler: ApiHandler<TArgs>,
  routeName: string,
  options?: WithErrorHandlerOptions,
): ApiHandler<TArgs>;
```

where

```ts
export type ApiHandler<TArgs extends readonly unknown[] = readonly unknown[]> = (
  req: NextRequest,
  ...routeArgs: TArgs
) => Promise<NextResponse>;

export type RouteParams<P extends Record<string, string | string[]> = ...> = {
  params: P;
};
```

- Static route → `TArgs = []`. Calling `wrapped(req, anything)` is a
  compile error.
- Dynamic route → `TArgs = [RouteParams<{ id: string }>]`. Passing the
  wrong key shape (`{ params: { slug: string } }`) is a compile error.
- Nested dynamic route → `TArgs = [RouteParams<{ groupId: string; id: string }>]`.
- No `any` escape hatch. No `as unknown as H` cast.

## 3. What shipped

| Piece                                           | File                                              |
| ----------------------------------------------- | ------------------------------------------------- |
| `RouteParams<P>` public helper type             | `portal/src/lib/api-handler.ts`                   |
| `ApiHandler<TArgs>` tuple-generic handler type  | `portal/src/lib/api-handler.ts`                   |
| `withErrorHandler<TArgs>` strict generic        | `portal/src/lib/api-handler.ts`                   |
| `L17-03` test case                              | `portal/src/lib/api-handler.test.ts`              |
| CI guard `npm run audit:api-handler-types`      | `tools/audit/check-api-handler-types.ts`          |
| This runbook                                    | `docs/runbooks/API_HANDLER_TYPING_RUNBOOK.md`     |

## 4. How to use it

### Static route

```ts
import { withErrorHandler } from "@/lib/api-handler";

async function _get(req: NextRequest): Promise<NextResponse> {
  // ...
  return NextResponse.json({ ok: true });
}

export const GET = withErrorHandler(_get, "api.platform.health.get");
```

### Dynamic route (`/api/thing/[id]`)

```ts
import { withErrorHandler, type RouteParams } from "@/lib/api-handler";

async function _patch(
  req: NextRequest,
  ctx: RouteParams<{ id: string }>,
): Promise<NextResponse> {
  const id = ctx.params.id; // ✅ typed
  // const slug = ctx.params.slug; // ❌ compile error
  // ...
}

export const PATCH = withErrorHandler(_patch, "api.things.patch");
```

### Nested dynamic route (`/api/foo/[groupId]/bar/[id]`)

```ts
async function _post(
  req: NextRequest,
  ctx: RouteParams<{ groupId: string; id: string }>,
): Promise<NextResponse> { ... }
```

### Catalogued use

`RouteParams<...>` is preferred because it documents intent and will be
the anchor for future improvements (e.g. auto-Zod-validation of
params, OpenAPI generation). For existing routes that already declare
`ctx: { params: { foo: string } }` inline, nothing forces a rewrite —
the structural type is identical, so the generic inference still flows
through. We recommend migrating to `RouteParams<>` when you next touch
the file.

## 5. Detection signals

| Signal                                                  | Surface                                                                          |
| ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| CI                                                      | `npm run audit:api-handler-types` (9 regressions) must stay green                |
| Tests                                                   | `npx vitest run portal/src/lib/api-handler.test.ts` — 12 tests incl. L17-03 case |
| Typecheck                                               | `npx tsc --noEmit` — any regression to `any[]` trips route typecheck             |
| Sentry                                                  | `route:` tags should still be populated — confirm after each rollout             |

## 6. Operational playbooks

### 6.1 Adding a new dynamic route

1. Create handler with `ctx: RouteParams<{ ... }>` annotation.
2. Wrap with `withErrorHandler(...)` as usual.
3. Push — CI will verify typing.

### 6.2 "My ctx doesn't match Next's `{ params }` shape"

Next.js occasionally evolves the route-handler signature (search-params
helpers, `request` as-first-arg, etc.). If a future Next.js passes a
different shape, you have two options:

- **Preferred**: update `RouteParams<>` to model the new shape (e.g. add
  a `searchParams` property) and migrate routes incrementally.
- **Escape hatch**: annotate the specific handler with
  `ctx: Record<string, unknown>` — still better than `any` and still
  checks that `ctx` is at least an object.

DO NOT reintroduce `any[]` in `withErrorHandler` — that's what L17-03
closed. If you are tempted, open a design review.

### 6.3 Pre-commit typecheck blows up on a handler touched today

Run `npx tsc --noEmit --project portal` locally, fix the `ctx.foo`
access site that used to silently compile, and resubmit. The fact that
TypeScript now rejects the typo is the feature, not a bug.

### 6.4 A route handler NEEDS to accept extras beyond `{ params }`

Next's route-handler protocol only defines `(req, ctx)` today. If we
eventually add instrumentation args, extend `ApiHandler<TArgs>` by
widening `TArgs` — do not fall back to `any[]`.

## 7. Rollback posture

This is a type-level hardening with **zero runtime behaviour change**.
The wrapper still forwards `...routeArgs` verbatim — all existing tests
pass unchanged. Rollback would mean reintroducing the type hole; we
only do it if Next.js ships a breaking protocol change that a narrower
type cannot model. In that case, prefer widening the generic bound
(e.g. `TArgs extends readonly unknown[]` → `TArgs extends unknown[]`)
over re-introducing `any`.

## 8. Invariants (enforced by CI)

- `api-handler.ts` exports `RouteParams`.
- `api-handler.ts` exports `ApiHandler<TArgs>` with
  `TArgs extends readonly unknown[]`.
- `withErrorHandler` is declared with a matching `TArgs` generic.
- Return type is `ApiHandler<TArgs>`; no `as unknown as H`.
- No `routeArgs: any[]` anywhere in the wrapper.
- The context-forwarding test uses `RouteParams<>`, not `any`.

## 9. Cross-references

- `L17-01` — financial routes must-use wrapper.
- `L17-05` — every `logger.error` (incl. the wrapper's call) reaches
  Sentry.
- `L13-06` — `x-request-id` propagation contract the wrapper owns.
- `L14-05` — canonical error envelope shape.
