/**
 * check-api-handler-types.ts
 *
 * L17-03 — CI guard enforcing that `portal/src/lib/api-handler.ts`
 * preserves handler-signature typing end-to-end and does NOT re-
 * introduce the `routeArgs: any[]` leak that defeated TypeScript's
 * contract checks for dynamic routes.
 *
 * The original implementation used
 *
 *   function withErrorHandler<
 *     H extends (req: NextRequest, ...routeArgs: any[]) => Promise<NextResponse>,
 *   >(handler: H, ...): H
 *
 * which let any `ctx.params.*` access through without a type error —
 * `/api/foo/[id]/route.ts` could read `ctx.params.slug` and the bug
 * would only surface at 500-time.
 *
 * The fix rewrites the wrapper as
 *
 *   function withErrorHandler<TArgs extends readonly unknown[]>(
 *     handler: (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse>,
 *     ...
 *   ): (req: NextRequest, ...routeArgs: TArgs) => Promise<NextResponse>
 *
 * plus the `RouteParams<P>` helper that dynamic routes annotate on
 * their `ctx` argument. The generic tuple inference carries the exact
 * shape (`{ params: { id: string } }`) from the caller through to the
 * wrapper's return type.
 *
 * Checks:
 *   1. `api-handler.ts` exports `RouteParams` (helper type) and
 *      `ApiHandler` (tuple-generic handler type).
 *   2. `withErrorHandler` is declared with `TArgs extends readonly unknown[]`
 *      and rejects the legacy `routeArgs: any[]` shape.
 *   3. The wrapper returns `ApiHandler<TArgs>` (not `H` via
 *      `as unknown as H` — that cast is the legacy workaround we
 *      removed).
 *   4. Tests use `RouteParams<...>` (not `any`) for the context arg of
 *      the dynamic-route forwarding test.
 *
 * Usage:
 *   npm run audit:api-handler-types
 */

import { readFileSync } from "node:fs";

type Check = { file: string; label: string; ok: boolean };

function has(src: string, needle: string | RegExp): boolean {
  return needle instanceof RegExp ? needle.test(src) : src.includes(needle);
}

function main(): number {
  const handlerFile = "portal/src/lib/api-handler.ts";
  const testFile = "portal/src/lib/api-handler.test.ts";

  let handlerSrc = "";
  let testSrc = "";
  try {
    handlerSrc = readFileSync(handlerFile, "utf8");
  } catch {
    console.error(`FATAL — could not read ${handlerFile}`);
    return 1;
  }
  try {
    testSrc = readFileSync(testFile, "utf8");
  } catch {
    console.error(`FATAL — could not read ${testFile}`);
    return 1;
  }

  console.log("L17-03 api-handler generic typing guard");

  const checks: Check[] = [];

  checks.push({
    file: handlerFile,
    label: "exports RouteParams helper type",
    ok: /export\s+type\s+RouteParams\b/.test(handlerSrc),
  });
  checks.push({
    file: handlerFile,
    label: "exports ApiHandler<TArgs> tuple-generic handler type",
    ok: /export\s+type\s+ApiHandler\s*<\s*TArgs\s+extends\s+readonly\s+unknown\[\]/
      .test(handlerSrc),
  });
  checks.push({
    file: handlerFile,
    label:
      "withErrorHandler is generic over `TArgs extends readonly unknown[]`",
    ok: /function\s+withErrorHandler\s*<\s*TArgs\s+extends\s+readonly\s+unknown\[\]\s*>/
      .test(handlerSrc),
  });
  checks.push({
    file: handlerFile,
    label: "withErrorHandler accepts an ApiHandler<TArgs>",
    ok: /handler\s*:\s*ApiHandler<\s*TArgs\s*>/.test(handlerSrc),
  });
  checks.push({
    file: handlerFile,
    label: "withErrorHandler returns ApiHandler<TArgs> (no `as unknown as H`)",
    ok:
      /\)\s*:\s*ApiHandler<\s*TArgs\s*>\s*\{/.test(handlerSrc) &&
      !/as\s+unknown\s+as\s+H/.test(handlerSrc),
  });
  checks.push({
    file: handlerFile,
    label:
      "does NOT re-introduce `routeArgs: any[]` signature (legacy bug shape)",
    ok: !/routeArgs\s*:\s*any\[\]/.test(handlerSrc),
  });
  checks.push({
    file: handlerFile,
    label:
      "does NOT re-introduce the legacy `H extends (req, ...any[])` bound",
    ok: !/H\s+extends\s*\(\s*req\s*:\s*NextRequest\s*,\s*\.\.\.\s*routeArgs\s*:\s*any\[\]/
      .test(handlerSrc),
  });

  checks.push({
    file: testFile,
    label: "context-forwarding test uses RouteParams (not `any`) for ctx",
    ok:
      /ctx\s*:\s*RouteParams</.test(testSrc) &&
      !/async\s*\(\s*_req\s*:\s*NextRequest\s*,\s*ctx\s*:\s*any\s*\)/.test(
        testSrc,
      ),
  });
  checks.push({
    file: testFile,
    label: "imports RouteParams from api-handler",
    ok: /RouteParams/.test(testSrc) && /from\s+"\.\/api-handler"/.test(testSrc),
  });

  const failed = checks.filter((c) => !c.ok);
  for (const c of checks) {
    const mark = c.ok ? "OK" : "FAIL";
    console.log(`  [${mark}] ${c.file}: ${c.label}`);
  }

  if (failed.length > 0) {
    console.error(`\n  FAIL — ${failed.length} regression(s)`);
    console.error(
      `\nSee docs/runbooks/API_HANDLER_TYPING_RUNBOOK.md and docs/audit/findings/L17-03-*.md.`,
    );
    return 1;
  }

  console.log(
    `\nOK — withErrorHandler preserves handler-signature typing (L17-03).`,
  );
  return 0;
}

process.exit(main());
