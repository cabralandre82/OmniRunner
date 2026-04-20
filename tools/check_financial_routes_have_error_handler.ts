/**
 * tools/check_financial_routes_have_error_handler.ts
 *
 * L17-01 — CI guard: garante que TODA rota financeira/platform crítica
 * em `portal/src/app/api/**` exporte seus verbos HTTP através do
 * wrapper `withErrorHandler` (definido em `portal/src/lib/api-handler.ts`).
 *
 * Falhar em wrappear deixa endpoints financeiros sem:
 *
 *   - Captura automática de erros pelo Sentry
 *   - Propagação consistente do header `x-request-id`
 *   - Envelope canônico `{ ok: false, error: { code, message, request_id } }`
 *     no formato definido em [14.5]
 *
 * ## Wrappers aceitos
 *
 *   1. `export const POST = withErrorHandler(_post, "...")`
 *      Forma canônica criada por L17-01.
 *
 *   2. `export const POST = wrapV1Handler(legacyPost)`
 *      Alias de versionamento (`/api/v1/swap` → `/api/swap`). O
 *      handler legado já está wrappeado, então o alias é seguro.
 *
 *   3. `export const POST = <qualquer expressão>` quando o arquivo
 *      importa `withErrorHandler` E o invoca em algum lugar — cobre
 *      `const handler = withErrorHandler(...); export const POST = handler`.
 *
 * Padrões INVÁLIDOS:
 *
 *   - `export async function POST(req: NextRequest) { ... }`
 *   - `export const POST = async (...) => { ... }` (sem wrapper)
 *   - `export default async function handler(...)`
 *
 * ## Escopo
 *
 * O guard valida apenas rotas com **risco financeiro/platform**
 * (`FINANCIAL_ROUTE_PATTERNS`). Rotas puramente operacionais
 * (workouts, training-plan, announcements, athletes-CRUD) são
 * reportadas como `info` mas não falham CI — ver follow-up L17-XX
 * para universalização.
 *
 * O script percorre o filesystem (sem dependências externas) para
 * poder rodar em CI sem `pnpm install` no portal/.
 *
 * ## Saída
 *
 *   - Exit 0 + 1 linha por rota (`ok` / `info` / `FAIL`) + summary.
 *   - Exit 1 se qualquer rota financeira não usar `withErrorHandler`.
 *
 * ## Uso
 *
 *   npx tsx tools/check_financial_routes_have_error_handler.ts
 *   npx tsx tools/check_financial_routes_have_error_handler.ts --quiet   # só FAIL
 *   npx tsx tools/check_financial_routes_have_error_handler.ts --json    # output JSON p/ CI
 *   npx tsx tools/check_financial_routes_have_error_handler.ts --strict  # falha em info também
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const REPO_ROOT = process.cwd();
const API_ROOT = join(REPO_ROOT, "portal", "src", "app", "api");

const HTTP_VERBS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"] as const;
type HttpVerb = (typeof HTTP_VERBS)[number];

/**
 * Routes deliberately exempted from the wrapper requirement. Paths are
 * relative to the repo root so they read clearly in PR reviews. Add a
 * justification comment when extending this list.
 */
const EXEMPT_ROUTES: ReadonlyArray<{ path: string; reason: string }> = [
  // currently empty — every route should use withErrorHandler. Webhook
  // routes can use it too because the wrapper only intercepts thrown
  // errors and is body-shape agnostic.
];

/**
 * Glob-like substring patterns identifying routes that are
 * financially or operationally critical. A route file matching ANY
 * of these patterns is required to wrap its exports with
 * `withErrorHandler` (or an accepted alias) — failure exits CI 1.
 *
 * Routes that don't match are still reported (severity `info`) for
 * visibility, but DO NOT fail the build. This keeps L17-01 narrowly
 * scoped to the financial surface called out in the audit while
 * leaving room for an incremental rollout to non-financial routes.
 */
const FINANCIAL_ROUTE_PATTERNS: ReadonlyArray<RegExp> = [
  /\/api\/swap\/route\.(t|j)sx?$/,
  /\/api\/custody(\/|$)/,
  /\/api\/distribute-coins\//,
  /\/api\/clearing\//,
  /\/api\/checkout\//,
  /\/api\/billing(-portal)?\//,
  /\/api\/auto-topup\//,
  /\/api\/financial\//,
  /\/api\/platform\//,
  /\/api\/gateway-preference\//,
  /\/api\/cron\/settle-clearing-batch\//,
  /\/api\/export\/financial\//,
  /\/api\/v1\//,
];

interface RouteCheck {
  file: string;
  isFinancial: boolean;
  exportedVerbs: HttpVerb[];
  unwrappedVerbs: HttpVerb[];
  ok: boolean;
  reason?: string;
}

function walk(dir: string, files: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      walk(full, files);
    } else if (st.isFile() && /route\.(t|j)sx?$/.test(entry)) {
      files.push(full);
    }
  }
  return files;
}

function isExempt(file: string): { exempt: boolean; reason?: string } {
  const rel = relative(REPO_ROOT, file);
  for (const e of EXEMPT_ROUTES) {
    if (rel === e.path) return { exempt: true, reason: e.reason };
  }
  return { exempt: false };
}

function isFinancialRoute(file: string): boolean {
  const rel = relative(REPO_ROOT, file).replace(/\\/g, "/");
  return FINANCIAL_ROUTE_PATTERNS.some((re) => re.test(`/${rel}`));
}

function checkFile(file: string): RouteCheck {
  const src = readFileSync(file, "utf8");
  const isFinancial = isFinancialRoute(file);
  const exempt = isExempt(file);
  if (exempt.exempt) {
    return {
      file,
      isFinancial,
      exportedVerbs: [],
      unwrappedVerbs: [],
      ok: true,
      reason: `exempt: ${exempt.reason}`,
    };
  }

  const exportedVerbs: HttpVerb[] = [];
  const unwrappedVerbs: HttpVerb[] = [];

  // Pre-compute file-level signals shared by every verb regex.
  const importsErrorHandler =
    /from\s+["']@\/lib\/api-handler["']/.test(src) && /\bwithErrorHandler\s*\(/.test(src);
  const usesV1Wrapper = /\bwrapV1Handler\s*\(/.test(src);

  for (const verb of HTTP_VERBS) {
    // Regex 1 — `export async function POST(...)` — never wrapped
    const reFn = new RegExp(`^\\s*export\\s+async\\s+function\\s+${verb}\\b`, "m");
    // Regex 2 — `export const POST = withErrorHandler(...)` — explicitly wrapped
    const reConstWrapped = new RegExp(
      `^\\s*export\\s+const\\s+${verb}\\s*=\\s*withErrorHandler\\b`,
      "m",
    );
    // Regex 3 — `export const POST = wrapV1Handler(...)` — v1 alias to a wrapped handler
    const reConstV1 = new RegExp(
      `^\\s*export\\s+const\\s+${verb}\\s*=\\s*wrapV1Handler\\b`,
      "m",
    );
    // Regex 4 — `export const POST = <anything else>` — needs further analysis
    const reConstAny = new RegExp(`^\\s*export\\s+const\\s+${verb}\\b`, "m");

    if (reFn.test(src)) {
      exportedVerbs.push(verb);
      unwrappedVerbs.push(verb);
      continue;
    }

    if (reConstWrapped.test(src)) {
      exportedVerbs.push(verb);
      continue;
    }

    if (reConstV1.test(src)) {
      exportedVerbs.push(verb);
      continue;
    }

    if (reConstAny.test(src)) {
      exportedVerbs.push(verb);
      // Trust local wrapping patterns:
      //   const handler = withErrorHandler(_post, "..."); export const POST = handler;
      // or the v1 alias case where the export ultimately runs through
      // `wrapV1Handler`.
      if (importsErrorHandler || usesV1Wrapper) continue;
      unwrappedVerbs.push(verb);
    }
  }

  return {
    file,
    isFinancial,
    exportedVerbs,
    unwrappedVerbs,
    ok: unwrappedVerbs.length === 0,
  };
}

function main() {
  const args = new Set(process.argv.slice(2));
  const quiet = args.has("--quiet");
  const json = args.has("--json");
  const strict = args.has("--strict");

  let files: string[];
  try {
    files = walk(API_ROOT);
  } catch (e) {
    console.error(
      `[L17-01] failed to scan ${relative(REPO_ROOT, API_ROOT)}: ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
    process.exit(2);
  }

  const results = files.map(checkFile).sort((a, b) => a.file.localeCompare(b.file));
  // Critical failures (must wrap): financial routes that aren't wrapped.
  const criticalFails = results.filter((r) => !r.ok && r.isFinancial);
  // Informational: non-financial routes still using raw `export async function`.
  const informational = results.filter((r) => !r.ok && !r.isFinancial);

  if (json) {
    const payload = {
      ok: criticalFails.length === 0 && (!strict || informational.length === 0),
      total: results.length,
      critical_failures: criticalFails.map((r) => ({
        file: relative(REPO_ROOT, r.file),
        unwrapped_verbs: r.unwrappedVerbs,
      })),
      informational: informational.map((r) => ({
        file: relative(REPO_ROOT, r.file),
        unwrapped_verbs: r.unwrappedVerbs,
      })),
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + "\n");
    process.exit(payload.ok ? 0 : 1);
  }

  if (!quiet) {
    for (const r of results) {
      const rel = relative(REPO_ROOT, r.file);
      if (r.ok) {
        const verbs = r.exportedVerbs.length > 0 ? r.exportedVerbs.join(",") : "—";
        const tag = r.isFinancial ? "ok* " : "ok  ";
        console.log(`  ${tag} ${rel}   [${verbs}]${r.reason ? ` (${r.reason})` : ""}`);
      } else if (r.isFinancial) {
        console.log(
          `  FAIL ${rel}   missing withErrorHandler on: ${r.unwrappedVerbs.join(", ")}`,
        );
      } else {
        console.log(
          `  info ${rel}   non-financial; missing wrapper on: ${r.unwrappedVerbs.join(", ")}`,
        );
      }
    }
  } else {
    for (const r of criticalFails) {
      const rel = relative(REPO_ROOT, r.file);
      console.log(`FAIL ${rel}   missing withErrorHandler on: ${r.unwrappedVerbs.join(", ")}`);
    }
  }

  const financialCount = results.filter((r) => r.isFinancial).length;
  console.log("");
  console.log(
    `[L17-01] scanned ${results.length} route file(s) (${financialCount} financial); ` +
      `${criticalFails.length} critical fail(s); ${informational.length} info; ` +
      `${EXEMPT_ROUTES.length} exempt`,
  );

  if (criticalFails.length > 0 || (strict && informational.length > 0)) {
    console.log("");
    console.log(
      "Fix: wrap the offending exports with `withErrorHandler` from `@/lib/api-handler`.",
    );
    console.log("See docs/audit/findings/L17-01-*.md for the canonical pattern.");
    process.exit(1);
  }
}

main();
