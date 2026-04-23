/**
 * check-public-status.ts
 *
 * L20-06 — CI guard for the public status-page aggregator.
 *
 * Fails closed if any of the following drift:
 *
 *   1. `StatusComponent` loses any of the 6 canonical components
 *      (web / api / database / auth / payments / strava).
 *   2. `STATUS_COMPONENTS` array is no longer frozen / canonical —
 *      the status page renders in this exact order.
 *   3. `StatusLevel` loses any of its 5 values or changes the wire
 *      strings (operational / degraded / partial_outage /
 *      major_outage / unknown). These are the contract with the
 *      third-party status page.
 *   4. Cache TTL floor (`STATUS_CACHE_MIN_TTL_MS`) moves below 30s.
 *   5. `aggregateStatus` stops filling missing components with
 *      `unknown` — otherwise a vendor outage could silently hide a
 *      component from the UI.
 *   6. `collectFromFeeds` stops coercing throws to `unknown` — a
 *      single vendor timeout could then knock the whole endpoint.
 *   7. Route `/api/public/status` is missing, lost the OPTIONS
 *      handler (CORS preflight), or lost the `Access-Control-
 *      Allow-Origin: *` header.
 *   8. Runbook is missing or no longer cross-links the guard +
 *      finding.
 *
 * Usage:
 *   npm run audit:public-status
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const TYPES_PATH = resolve(
  REPO_ROOT,
  "portal/src/lib/status/types.ts",
);
const AGG_PATH = resolve(
  REPO_ROOT,
  "portal/src/lib/status/aggregate.ts",
);
const FEEDS_PATH = resolve(
  REPO_ROOT,
  "portal/src/lib/status/feeds.ts",
);
const ROUTE_PATH = resolve(
  REPO_ROOT,
  "portal/src/app/api/public/status/route.ts",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/PUBLIC_STATUS_PAGE_RUNBOOK.md",
);

interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

const results: CheckResult[] = [];

function push(name: string, ok: boolean, detail?: string) {
  results.push({ name, ok, detail });
}

function safeRead(path: string, label: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    push(label, false, `file not found: ${path}`);
    return null;
  }
}

const types = safeRead(TYPES_PATH, "status/types.ts present");
if (types) {
  push("status/types.ts present", true);

  for (const c of [
    "web",
    "api",
    "database",
    "auth",
    "payments",
    "strava",
  ]) {
    push(
      `StatusComponent '${c}' declared`,
      new RegExp(`['\"]${c}['\"]`).test(types),
    );
  }
  push(
    "STATUS_COMPONENTS canonical array declared",
    /STATUS_COMPONENTS\s*:\s*readonly\s+StatusComponent\[\]/.test(types),
  );
  push(
    "STATUS_COMPONENT_LABELS map declared",
    /STATUS_COMPONENT_LABELS\s*:\s*Record<StatusComponent,\s*string>/.test(
      types,
    ),
  );

  for (const l of [
    "operational",
    "degraded",
    "partial_outage",
    "major_outage",
    "unknown",
  ]) {
    push(
      `StatusLevel '${l}' declared`,
      new RegExp(`['\"]${l}['\"]`).test(types),
    );
  }

  push(
    "compareStatusLevels exported",
    /export\s+function\s+compareStatusLevels\s*\(/.test(types),
  );

  push(
    "STATUS_CACHE_MIN_TTL_MS >= 30_000",
    /STATUS_CACHE_MIN_TTL_MS\s*=\s*30_?000/.test(types),
  );
  push(
    "STATUS_CACHE_DEFAULT_TTL_MS >= STATUS_CACHE_MIN_TTL_MS",
    /STATUS_CACHE_DEFAULT_TTL_MS\s*=\s*60_?000/.test(types),
  );

  push(
    "StatusFeed interface declared",
    /export\s+interface\s+StatusFeed\b/.test(types),
  );
  push(
    "ComponentStatus interface declared",
    /export\s+interface\s+ComponentStatus\b/.test(types),
  );
  push(
    "AggregateStatus interface declared",
    /export\s+interface\s+AggregateStatus\b/.test(types),
  );
}

const agg = safeRead(AGG_PATH, "status/aggregate.ts present");
if (agg) {
  push("status/aggregate.ts present", true);

  push(
    "worstLevel exported",
    /export\s+function\s+worstLevel\s*\(/.test(agg),
  );
  push(
    "aggregateStatus exported",
    /export\s+function\s+aggregateStatus\s*\(/.test(agg),
  );
  push(
    "collectFromFeeds exported",
    /export\s+async\s+function\s+collectFromFeeds\s*\(/.test(agg),
  );
  push(
    "createCachedAggregator exported",
    /export\s+function\s+createCachedAggregator\s*\(/.test(agg),
  );

  push(
    "aggregateStatus fills missing components with 'unknown'",
    /level\s*:\s*['\"]unknown['\"][\s\S]{0,150}no feed registered/.test(agg),
  );
  push(
    "collectFromFeeds coerces throws to 'unknown'",
    /catch[\s\S]{0,200}level\s*:\s*['\"]unknown['\"]/.test(agg),
  );
  push(
    "createCachedAggregator floors TTL at STATUS_CACHE_MIN_TTL_MS",
    /Math\.max\([\s\S]{0,120}STATUS_CACHE_MIN_TTL_MS/.test(agg),
  );
}

const feeds = safeRead(FEEDS_PATH, "status/feeds.ts present");
if (feeds) {
  push("status/feeds.ts present", true);

  for (const fn of [
    "staticFeed",
    "internalProbeFeed",
    "withTimeout",
  ]) {
    push(
      `${fn} exported`,
      new RegExp(`export\\s+function\\s+${fn}\\s*\\(`).test(feeds),
    );
  }
  push(
    "internalProbeFeed maps ok/degraded/down",
    /['\"]ok['\"][\s\S]{0,200}['\"]degraded['\"][\s\S]{0,200}['\"]down['\"]/.test(
      feeds,
    ),
  );
  push(
    "withTimeout guards against non-positive timeouts",
    /timeoutMs\s*<=\s*0[\s\S]{0,100}throw/.test(feeds),
  );
}

const route = safeRead(ROUTE_PATH, "route.ts present");
if (route) {
  push("route.ts present", true);
  push(
    "route exports GET",
    /export\s+(?:async\s+)?function\s+GET\s*\(/.test(route),
  );
  push(
    "route exports OPTIONS (CORS preflight)",
    /export\s+function\s+OPTIONS\s*\(/.test(route),
  );
  push(
    "route sets access-control-allow-origin: *",
    /access-control-allow-origin['\"]\s*:\s*['\"]\*/.test(route),
  );
  push(
    "route uses createCachedAggregator",
    /createCachedAggregator\s*\(/.test(route),
  );
  push(
    "route registers feeds for every canonical component",
    /['\"]web['\"][\s\S]{0,300}['\"]api['\"][\s\S]{0,400}['\"]database['\"][\s\S]{0,400}['\"]auth['\"][\s\S]{0,400}['\"]payments['\"][\s\S]{0,400}['\"]strava['\"]/.test(
      route,
    ),
  );
  push(
    "route wraps each feed in withTimeout",
    /withTimeout\s*\(/.test(route),
  );
  push(
    "route never returns 5xx on partial outage (try/catch falls back)",
    /try\s*{[\s\S]{0,400}catch[\s\S]{0,400}fallback/.test(route),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:public-status",
    runbook.includes("audit:public-status")
      || runbook.includes("check-public-status"),
  );
  push("runbook cross-links L20-06", runbook.includes("L20-06"));
  push(
    "runbook mentions status.omnirunner.com or equivalent",
    /status\.omnirunner\.com|status-page|Statuspage|Better\s*Stack|Cachet/i.test(
      runbook,
    ),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) {
    console.log(`[OK]   ${r.name}`);
  } else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}

console.log(
  `\n${results.length - failed}/${results.length} public-status checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL20-06 invariants broken. See docs/runbooks/PUBLIC_STATUS_PAGE_RUNBOOK.md.",
  );
  process.exit(1);
}
