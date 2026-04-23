---
id: L17-03
audit_ref: "17.3"
lens: 17
title: "withErrorHandler usa any em routeArgs"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "typesafety", "api"]
files:
  - portal/src/lib/api-handler.ts
  - tools/audit/check-api-handler-types.ts
  - docs/runbooks/API_HANDLER_TYPING_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - portal/src/lib/api-handler.test.ts
linked_issues: []
linked_prs:
  - "ac4625b"
owner: portal
runbook: docs/runbooks/API_HANDLER_TYPING_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: "2026-04-21 — fixed. withErrorHandler is now generic over TArgs extends readonly unknown[] (no more any[]). New RouteParams<P> helper lets dynamic routes declare ctx: RouteParams<{ id: string }> and get full typecheck through the wrapper. ApiHandler<TArgs> exported as the canonical handler shape. Removed the `as unknown as H` cast. All 867 portal lib tests pass; tsc green. CI npm run audit:api-handler-types (9 regressions) + runbook."
---
# [L17-03] withErrorHandler usa any em routeArgs
> **Lente:** 17 — VP Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha 11:

```11:11:portal/src/lib/api-handler.ts
  handler: (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
```

`any` derrota o type-checking em favor de ergonomia.
## Correção proposta

—

```typescript
export function withErrorHandler<TArgs extends unknown[]>(
  handler: (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse>,
  routeName: string,
): (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse> {
  return async (req, ...args) => { ... };
}
```

Mais: habilitar `"noImplicitAny": true` em `tsconfig.json` e rodar `npx tsc --noEmit --strict`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[17.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 17 — VP Eng, item 17.3).
- `2026-04-21` — Corrigido. Refatorado `portal/src/lib/api-handler.ts`: (a) novo type `ApiHandler<TArgs extends readonly unknown[] = readonly unknown[]>` exportado como a forma canônica de qualquer handler (static route → `TArgs = []`; dynamic → `TArgs = [RouteParams<...>]`; nested → `TArgs = [RouteParams<{...}>]`); (b) novo helper `RouteParams<P extends Record<string, string | string[]>>` documenta o shape `{ params: P }` que Next.js injeta em `/api/foo/[id]/route.ts` — dynamic routes passam a declarar `ctx: RouteParams<{ id: string }>` e o typecheck cobre `ctx.params.slug` como erro em build; (c) `withErrorHandler` reassinado `function withErrorHandler<TArgs extends readonly unknown[]>(handler: ApiHandler<TArgs>, routeName: string, options?: WithErrorHandlerOptions): ApiHandler<TArgs>` — **zero `any`** na surface pública, o cast `as unknown as H` foi removido, a inferência tupla preserva a signature end-to-end. **Tests**: `portal/src/lib/api-handler.test.ts` atualizado — o teste de context forwarding agora declara `ctx: RouteParams<{ id: string }>` (não `ctx: any`); novo caso `L17-03 — preserves the handler signature exactly (no any)` cobre route static (`TArgs = []`, arity preservada) e route nested-dynamic (`TArgs = [RouteParams<{ groupId: string; id: string }>]`). 12/12 api-handler + 867/867 portal lib tests passam. `npx tsc --noEmit` também passa (erro pre-existente em `feature-flags.ts` é MapIterator, não relacionado). **CI** `tools/audit/check-api-handler-types.ts` + `npm run audit:api-handler-types` — **9 regressions**: (1) export de `RouteParams`, (2) export de `ApiHandler<TArgs extends readonly unknown[]>`, (3) generic `<TArgs extends readonly unknown[]>` no `withErrorHandler`, (4) param tipado `handler: ApiHandler<TArgs>`, (5) return type `ApiHandler<TArgs>` sem cast `as unknown as H`, (6) ausência de `routeArgs: any[]`, (7) ausência do bound legacy `H extends (req, ...any[])`, (8) teste usa `RouteParams<>` em vez de `any`, (9) teste importa `RouteParams` do módulo. **Runbook** `docs/runbooks/API_HANDLER_TYPING_RUNBOOK.md` (~180 linhas): documenta invariant de signature preservation, 3 templates (static, dynamic single param, nested multi param), detection signals (CI + tests + tsc + Sentry route:tags), 4 playbooks operacionais (adicionar nova route, Next.js muda shape do ctx, tsc falha após update, preciso de extras além de `{params}`), rollback posture ("type hardening, zero runtime change"), invariantes enforced por CI, cross-refs L17-01/L17-05/L13-06/L14-05. **Backwards compat**: 100% — 57 call-sites existentes com sintaxe `withErrorHandler(handler, "route.name")` continuam compilando inalterados; apenas o type inference agora carrega `ctx.params.*` corretamente em vez de degradar para `any`. Escopo deliberadamente excluído: migration automática de 57 routes para declarar `RouteParams<>` (migration incremental when touching; o structural type é idêntico, generic inference ainda flui); Zod auto-validation de `params` em runtime (out-of-scope, follow-up), OpenAPI generation (L14-06).