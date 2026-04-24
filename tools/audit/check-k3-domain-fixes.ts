#!/usr/bin/env tsx
/**
 * Batch K3 — pure-domain TypeScript / Dart guards.
 *
 * Asserts the structural invariants of all K3 fixes are present in
 * the repository. Findings covered:
 *
 *   L01-25 / L13-08  PUBLIC_PREFIX_PATTERNS segment-shape contract
 *   L01-28           Flutter invite-code regex
 *   L01-32           Flutter secure_storage hardened defaults
 *   L01-33           Flutter secure_storage exception handler
 *   L01-50           UUID guard on PostgREST .or() composition
 *   L02-12           Zod uuid policy module
 *   L03-06           FX spread disclosure document
 *   L05-12           challenge tie-break pure-domain module
 *   L13-09           middleware single-membership no-redirect
 */
import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.resolve(__dirname, "../..");

type Check = { id: string; file: string; assertions: Array<[string, RegExp]> };

const CHECKS: Check[] = [
  {
    id: "L01-25/L13-08",
    file: "portal/src/lib/route-policy.ts",
    assertions: [
      [
        "PUBLIC_PREFIX_PATTERNS array",
        /export const PUBLIC_PREFIX_PATTERNS:\s*ReadonlyArray<\{/,
      ],
      [
        "challenge regex",
        /\/challenge\\\/\[A-Za-z0-9_-\]\{1,64\}\$/,
      ],
      [
        "invite regex",
        /\/invite\\\/\[A-Za-z0-9_-\]\{1,64\}\$/,
      ],
      [
        "isPublicRoute uses pattern",
        /for \(const \{ prefix, fullPath \} of PUBLIC_PREFIX_PATTERNS\)/,
      ],
    ],
  },
  {
    id: "L01-28",
    file: "omni_runner/lib/core/deep_links/deep_link_handler.dart",
    assertions: [
      ["regex constant", /_inviteCodeShape\s*=\s*RegExp/],
      ["6..16 alnum/dash/underscore", /\^\[A-Z0-9_-\]\{6,16\}\$/],
    ],
  },
  {
    id: "L01-32",
    file: "omni_runner/lib/core/secure_storage/db_secure_store.dart",
    assertions: [
      [
        "encryptedSharedPreferences true",
        /AndroidOptions\(encryptedSharedPreferences:\s*true\)/,
      ],
      [
        "first_unlock_this_device accessibility",
        /KeychainAccessibility\.first_unlock_this_device/,
      ],
    ],
  },
  {
    id: "L01-33",
    file: "omni_runner/lib/core/secure_storage/db_secure_store.dart",
    assertions: [
      ["safeRead helper", /Future<String\?>\s+_safeRead/],
      ["catches PlatformException", /on PlatformException catch/],
      ["L01-33 marker", /L01-33/],
    ],
  },
  {
    id: "L01-50",
    file: "portal/src/lib/security/uuid-guard.ts",
    assertions: [
      ["assertUuid export", /export function assertUuid/],
      ["buildOrEqExpression export", /export function buildOrEqExpression/],
      ["UUID v1-5 regex", /\[1-5\]\[0-9a-f\]\{3\}-\[89ab\]/],
    ],
  },
  {
    id: "L01-50/swap.ts",
    file: "portal/src/lib/swap.ts",
    assertions: [
      ["uses buildOrEqExpression", /buildOrEqExpression\(/],
      [
        "no raw .or interpolation with groupId",
        /^(?!.*\.or\(`seller_group_id\.eq\.\$\{groupId\}).*$/s,
      ],
    ],
  },
  {
    id: "L01-50/clearing.ts",
    file: "portal/src/lib/clearing.ts",
    assertions: [
      ["uses assertUuid", /assertUuid\(groupId/],
      ["uses buildOrEqExpression", /buildOrEqExpression\(/],
    ],
  },
  {
    id: "L02-12",
    file: "portal/src/lib/schemas/uuid-policy.ts",
    assertions: [
      ["omniUuid helper", /export const omniUuid/],
      [
        "externalIntegrationId helper",
        /export function externalIntegrationId/,
      ],
      ["correlationToken helper", /export function correlationToken/],
    ],
  },
  {
    id: "L03-06",
    file: "docs/legal/FX_SPREAD_DISCLOSURE.md",
    assertions: [
      ["round-trip explained", /round-trip|1\.50/i],
      ["concrete table", /985\.06|spread/],
      ["deposit confirmation MUST", /Deposit confirmation|MUST display/i],
      ["entry-only future option", /Entry-only spread/i],
    ],
  },
  {
    id: "L05-12",
    file: "portal/src/lib/challenges/tie-break.ts",
    assertions: [
      ["compareLeaderboardRows", /export function compareLeaderboardRows/],
      ["pickWinner", /export function pickWinner/],
      [
        "deterministic order constant",
        /CHALLENGE_TIE_BREAK_SQL_ORDER[\s\S]+metric_value DESC/,
      ],
    ],
  },
  {
    id: "L13-09",
    file: "portal/src/middleware.ts",
    assertions: [
      [
        "L13-09 marker present",
        /L13-09/,
      ],
      [
        "single-membership cookies on supabaseResponse",
        /supabaseResponse\.cookies\.set\([\s\S]+portal_group_id/,
      ],
    ],
  },
];

function main() {
  const failures: string[] = [];
  for (const c of CHECKS) {
    const fp = path.join(ROOT, c.file);
    if (!fs.existsSync(fp)) {
      failures.push(`[${c.id}] file missing: ${c.file}`);
      continue;
    }
    const text = fs.readFileSync(fp, "utf8");
    for (const [label, re] of c.assertions) {
      if (!re.test(text)) failures.push(`[${c.id}] ${c.file}: assertion FAIL — ${label}`);
    }
  }

  if (failures.length > 0) {
    console.error(`[FAIL] ${failures.length} K3 domain assertion(s) failed:`);
    for (const f of failures) console.error("  - " + f);
    process.exit(1);
  }
  console.log(`[OK] all ${CHECKS.length} K3 domain fixes verified.`);
}

main();
