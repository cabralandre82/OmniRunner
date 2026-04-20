---
id: L06-02
audit_ref: "6.2"
lens: 6
title: "Health check exibe contagem exata de violações (info leak operacional)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "portal", "migration", "testing", "ciso", "observability"]
files:
  - portal/src/app/api/health/route.ts
  - portal/src/app/api/platform/health/route.ts
  - portal/public/openapi.json
  - docs/PORTAL_API.md
  - portal/e2e/health.spec.ts
correction_type: code
test_required: true
tests:
  - portal/src/app/api/health/route.test.ts
  - portal/src/app/api/platform/health/route.test.ts
  - portal/e2e/health.spec.ts
linked_issues: []
linked_prs: ["810b1fc"]
owner: platform
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed with a clean split between the PUBLIC uptime probe and the
  ADMIN detailed snapshot — no information leak, no regression for
  external monitors, no duplication of logic:

    1. Public `GET /api/health` is now intentionally opaque.
       Response is locked to `{ status, ts }` only. Uptime probes
       (Vercel, k6 smoke at `tools/load-tests/scenarios/api-health.js`,
       any external pinger) still read the HTTP status code (200 vs
       503) as their primary signal and the `status` string
       ("ok" | "degraded" | "down") for human-readable severity.
       ALL other fields were removed:
         • `latencyMs`     — fingerprinting + DB-capacity signal.
         • `checks.db`     — "unreachable" string = DB outage oracle.
         • `checks.invariants: "N violation(s)"` — THE core leak.
           Let an attacker monitor clearing/reconcile activity
           without ever authenticating, and time follow-up attacks
           to known-unstable moments (e.g. during a reconcile-wallets
           run, or mid-custody failure).
       The underlying checks still run server-side so the HTTP
       status code differentiates ok/degraded/down; their results
       are emitted to our own telemetry pipeline (`metrics.gauge`
       on `health.db`, `health.invariants`, `health.invariant_violations`)
       but NEVER to the HTTP body of the public endpoint.

    2. Admin `GET /api/platform/health` is the authenticated
       counterpart. Returns the previously-public payload (minus
       the "N violation(s)" string form) gated behind
       `platform_admins` membership — same pattern as
       `/api/platform/cron-health` (L06-04) and
       `/api/platform/cron-sla` (L12-04), so operators have muscle
       memory. Response shape:
         { ok, status, ts, latency_ms,
           checks: { db: "connected"|"unreachable",
                     invariants: "healthy"|"violations" },
           invariant_count, request_id, checked_at }
       The violation COUNT is still exposed — but only to
       platform admins who could already enumerate the full
       per-row detail via `GET /api/platform/invariants` anyway,
       so there is no net disclosure widening.

    3. Tests lock the leak shut:
       • `src/app/api/health/route.test.ts` — 8 cases asserting
         `Object.keys(body)` is EXACTLY `["status","ts"]` under
         healthy, degraded (violations), and down conditions, plus
         regex guards against the literal strings `violation` /
         `violation(s)` / `N violation(s)`. A future regression
         that re-adds `checks` or `latencyMs` fails these tests.
       • `src/app/api/platform/health/route.test.ts` — 8 cases
         covering 401/403 (and asserting the service client is
         NEVER instantiated pre-auth), 200 ok + payload shape,
         503 degraded with exact count, 503 down on db error,
         no leaky state between calls, and enum boundary
         assertions for `checks.invariants`.
       • `portal/e2e/health.spec.ts` — updated Playwright spec
         asserts the stripped public payload AND that
         `/api/platform/health` returns 401/403/404 without a
         session, preventing accidental public exposure via
         middleware regressions.

    4. Contracts updated:
       • `portal/public/openapi.json` — `/api/health` now declares
         `additionalProperties: false` and enumerates ONLY
         `status` + `ts`; `/api/platform/health` is a new entry
         under tags `["Platform Admin","System"]` with full
         schema + 401/403 responses. Covers the L14-01 coverage
         gate automatically (no new undocumented paths).
       • `docs/PORTAL_API.md` — `## Health` section rewritten to
         spell out the public/admin split and explicitly call
         out that the stripped payload is by design (L06-02,
         L01-07) so future reviewers don't "restore" the fields.

  Also closes the Medium-severity sibling L01-07 (CISO lens) which
  documented the same leak from the reconnaissance-risk angle —
  both live in the same file change and share the test harness.

  Verification:
    • 16 Vitest cases (8 public + 8 admin) pass.
    • Full portal suite 1441/1441 green (4 todos) — no regression.
    • `npx tsc --noEmit` produces no NEW errors (only the
      pre-existing `lib/feature-flags.ts(69,22)` MapIterator note
      already tracked separately).
    • ESLint clean on all L06-02 surface files.
    • `tools/audit/verify.ts` → 348/348 findings validated.

  Tracked progress: 98/348 fixed after this finding.
---
# [L06-02] Health check exibe contagem exata de violações (info leak operacional)
> **Lente:** 6 — COO · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** ✅ fixed (2026-04-21)
**Camada:** Portal API + OpenAPI contract

## Achado

`portal/src/app/api/health/route.ts` era público (nenhum auth, listado em
`PUBLIC_PREFIXES` do middleware e no exempt list de CSRF porque uptime
probes não carregam cookie). Retornava:

```json
{
  "status": "ok" | "degraded" | "down",
  "ts": 1709136000000,
  "latencyMs": 42,
  "checks": {
    "db": "connected" | "unreachable",
    "invariants": "healthy" | "7 violation(s)"
  }
}
```

Um atacante anônimo podia:

- **Inferir clearing/reconcile em curso** observando o valor de
  `invariants` mudar de `"healthy"` → `"3 violation(s)"` → `"healthy"`
  durante a janela de execução de um cron.
- **Fingerprintar a camada de DB** via `latencyMs` (p50/p95 estáveis
  permitem identificar instância Supabase, dimensionar ataque).
- **Detectar outage de DB** via `checks.db: "unreachable"` (oracle
  gratuito para "agora é o momento" de extorsão / DDoS coordenado).

## Risco / Impacto

- **Information disclosure crítico** — o sinal `"N violation(s)"` é a
  métrica mais sensível da plataforma (saúde de custódia); expor ela
  a scraping público dá timing de ataque a qualquer adversário
  externo ou ex-funcionário.
- **Extorsão** — "paga ou divulgo o painel mostrando que vocês
  estão com 7 violações de invariante há 4 horas".
- **Reconhecimento para ataques coordenados** — p99 de latência
  em `latencyMs` pode ser usado para timing side-channel de
  operações financeiras em curso.

## Correção implementada

- `portal/src/app/api/health/route.ts` — resposta pública reduzida a
  `{ status, ts }`. Checks continuam rodando server-side para
  diferenciar 200/503; resultados só vão para telemetria interna.
- `portal/src/app/api/platform/health/route.ts` — novo endpoint
  admin-only com o payload detalhado (latency_ms + checks +
  invariant_count) gated por `platform_admins`, seguindo o mesmo
  padrão de `/api/platform/cron-health` e `/api/platform/cron-sla`.
- Tests — 8 Vitest no endpoint público (assertam shape ESTRITO
  `["status","ts"]` e blindam contra regressão de qualquer campo
  extra), 8 Vitest no endpoint admin (401/403 antes do service
  client, 200/503 com detalhe, stateless), e Playwright e2e
  atualizado.
- Contratos — `portal/public/openapi.json` reflete o split
  (`additionalProperties: false` no público; schema completo
  no admin). `docs/PORTAL_API.md` `## Health` reescrito.

## Teste de regressão

Qualquer PR que adicione campos ao `/api/health` público falha em:

- `route.test.ts` linha `expect(Object.keys(json).sort()).toEqual(["status","ts"])`
- `route.test.ts` regex `not.toMatch(/violation/i)`
- `e2e/health.spec.ts` `expect(Object.keys(body).sort()).toEqual(["status","ts"])`
- validação OpenAPI (`additionalProperties: false`)

## Referência narrativa

Contexto completo em [`docs/audit/parts/`](../parts/) — anchor `[6.2]`.

## Histórico

- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.2).
- `2026-04-21` — Fixed: public `/api/health` reduzido a `{status, ts}`,
  admin `/api/platform/health` criado, L01-07 fechado pelo mesmo commit.
