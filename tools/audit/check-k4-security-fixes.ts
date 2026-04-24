#!/usr/bin/env tsx
/**
 * Batch K4 — middleware / API / security guards.
 *
 * Asserts the structural invariants of all K4 fixes are present in
 * the repository. Findings covered:
 *
 *   L01-10  safeNext open-redirect guard on /api/auth/callback
 *   L01-21  rateLimit fail-closed mode for financial endpoints
 *   L01-26  middleware platform_role cache (5 min TTL)
 *   L02-11  module-cached service-role Supabase client
 *   L02-15  request-aware getRedis() (60 s recheck)
 *   L11-13  lockfile drift CI guard
 *   L11-14  omni_runner/pubspec.lock committed (not ignored)
 */
import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.resolve(__dirname, "../..");

type Check = { id: string; file: string; assertions: Array<[string, RegExp]> };

const CHECKS: Check[] = [
  {
    id: "L01-10",
    file: "portal/src/lib/security/safe-next.ts",
    assertions: [
      ["safeNext exported", /export function safeNext\(/],
      ["allowlist regex", /ALLOWED_NEXT/],
      ["rejects protocol-relative", /FORBIDDEN_PREFIXES/],
    ],
  },
  {
    id: "L01-10 wired",
    file: "portal/src/app/api/auth/callback/route.ts",
    assertions: [
      ["imports safeNext", /from "@\/lib\/security\/safe-next"/],
      ["uses safeNext", /safeNext\(searchParams\.get\("next"\)\)/],
    ],
  },
  {
    id: "L01-21",
    file: "portal/src/lib/rate-limit.ts",
    assertions: [
      ["fail_closed option", /onMissingRedis\?: "degrade" \| "fail_closed"/],
      ["rateLimitFailClosed export", /export async function rateLimitFailClosed/],
      ["telemetry counter", /rateLimitTelemetrySnapshot/],
    ],
  },
  {
    id: "L01-21 wired",
    file: "portal/src/app/api/custody/withdraw/route.ts",
    assertions: [["fail_closed used", /onMissingRedis: "fail_closed"/]],
  },
  {
    id: "L01-26",
    file: "portal/src/lib/route-policy-cache.ts",
    assertions: [
      ["platform role cache", /getCachedPlatformRole/],
      ["5 min TTL", /PLATFORM_ROLE_DEFAULT_TTL_MS = 300_000/],
      ["invalidator", /invalidatePlatformRole/],
    ],
  },
  {
    id: "L01-26 wired",
    file: "portal/src/middleware.ts",
    assertions: [
      ["middleware imports cache", /getCachedPlatformRole/],
      ["middleware sets cache", /setCachedPlatformRole\(user\.id/],
    ],
  },
  {
    id: "L02-11",
    file: "portal/src/lib/supabase/service.ts",
    assertions: [
      ["module cache", /let _client: ServiceClient \| null = null/],
      ["L02-11 marker", /L02-11/],
      ["test-only reset", /__resetServiceClientForTests/],
    ],
  },
  {
    id: "L02-15",
    file: "portal/src/lib/redis.ts",
    assertions: [
      ["recheck interval const", /RECHECK_INTERVAL_MS = 60_000/],
      ["isRedisAvailable export", /export function isRedisAvailable/],
      ["L02-15 marker", /L02-15/],
    ],
  },
  {
    id: "L11-13",
    file: "tools/audit/check-lockfile-drift.ts",
    assertions: [
      ["WORKSPACES list", /const WORKSPACES: ReadonlyArray<string>/],
      ["pinned() helper", /function pinned\(version: string\)/],
    ],
  },
  {
    id: "L11-14 .gitignore",
    file: ".gitignore",
    assertions: [
      [
        "pubspec.lock NOT ignored marker",
        /pubspec\.lock.{0,200}intentionally NOT ignored/s,
      ],
    ],
  },
];

let failed = 0;
let passed = 0;
const failures: string[] = [];

for (const { id, file, assertions } of CHECKS) {
  const p = path.join(ROOT, file);
  if (!fs.existsSync(p)) {
    failed++;
    failures.push(`${id}: file missing — ${file}`);
    continue;
  }
  const content = fs.readFileSync(p, "utf8");
  for (const [label, rx] of assertions) {
    if (!rx.test(content)) {
      failed++;
      failures.push(`${id} (${file}): assertion failed — ${label}`);
    } else {
      passed++;
    }
  }
}

// Extra invariant: omni_runner/pubspec.lock must exist as a tracked file
const pubspecLock = path.join(ROOT, "omni_runner/pubspec.lock");
if (!fs.existsSync(pubspecLock)) {
  failed++;
  failures.push(
    "L11-14: omni_runner/pubspec.lock is missing — Flutter docs require it for app packages",
  );
} else {
  passed++;
}

if (failed > 0) {
  console.error(`[FAIL] ${failed} K4 invariants failed (passed: ${passed}):`);
  for (const f of failures) console.error("  - " + f);
  process.exit(1);
}

console.log(`[OK] all ${passed} K4 invariants verified.`);
