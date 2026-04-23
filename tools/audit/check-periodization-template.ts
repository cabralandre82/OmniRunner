/**
 * check-periodization-template.ts
 *
 * L23-06 — CI guard for the periodization template surface.
 *
 * Fails closed if:
 *
 *   1. `types.ts` is missing or one of the 4 shipped race targets
 *      disappears.
 *   2. A race spec's `minTotalWeeks`/`maxTotalWeeks` range is
 *      inverted or lacks `peakWeeklyKmByLevel` entries for all 3
 *      athlete levels.
 *   3. `generatePeriodization` or `assertPeriodizationPlanValid` is
 *      removed from the generator file.
 *   4. The wizard API route `/api/training-plan/wizard` is missing
 *      or no longer auth-gates via `supabase.auth.getUser()`.
 *   5. `PERIODIZATION_WIZARD_RUNBOOK.md` is missing or no longer
 *      cross-links this guard.
 *
 * Usage:
 *   npm run audit:periodization-template
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const TYPES_PATH = resolve(
  REPO_ROOT,
  "portal/src/lib/periodization/types.ts",
);
const GENERATOR_PATH = resolve(
  REPO_ROOT,
  "portal/src/lib/periodization/generate-periodization.ts",
);
const ROUTE_PATH = resolve(
  REPO_ROOT,
  "portal/src/app/api/training-plan/wizard/route.ts",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md",
);

const REQUIRED_RACE_TARGETS = [
  "fiveK",
  "tenK",
  "halfMarathon",
  "marathon",
];

const REQUIRED_LEVELS = ["beginner", "intermediate", "advanced"];

const REQUIRED_CYCLES = ["base", "build", "peak", "taper"];

interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

const results: CheckResult[] = [];

function pushResult(name: string, ok: boolean, detail?: string) {
  results.push({ name, ok, detail });
}

function readOr(
  path: string,
  label: string,
): { content?: string; present: boolean } {
  try {
    return { content: readFileSync(path, "utf8"), present: true };
  } catch {
    pushResult(label, false, `file not found: ${path}`);
    return { present: false };
  }
}

const typesFile = readOr(TYPES_PATH, "types file present");
if (typesFile.present && typesFile.content) {
  const src = typesFile.content;
  pushResult("types file present", true);

  for (const t of REQUIRED_RACE_TARGETS) {
    const pattern = new RegExp(`\\b${t}\\s*:\\s*{`);
    pushResult(
      `RACE_SPECS declares "${t}"`,
      pattern.test(src),
      pattern.test(src) ? undefined : `missing RACE_SPECS.${t}`,
    );
  }

  for (const t of REQUIRED_RACE_TARGETS) {
    const specBlock = extractRaceSpecBlock(src, t);
    if (!specBlock) {
      pushResult(
        `spec ${t} has full peakWeeklyKmByLevel map`,
        false,
        `could not isolate RACE_SPECS.${t} block`,
      );
      continue;
    }
    const missing = REQUIRED_LEVELS.filter(
      (lvl) => !new RegExp(`\\b${lvl}\\s*:`).test(specBlock),
    );
    pushResult(
      `spec ${t} has full peakWeeklyKmByLevel map`,
      missing.length === 0,
      missing.length === 0
        ? undefined
        : `missing level(s): ${missing.join(", ")}`,
    );
    const minMatch = specBlock.match(/minTotalWeeks\s*:\s*(\d+)/);
    const maxMatch = specBlock.match(/maxTotalWeeks\s*:\s*(\d+)/);
    pushResult(
      `spec ${t} has min/max totalWeeks`,
      !!minMatch && !!maxMatch,
      !minMatch || !maxMatch
        ? `missing minTotalWeeks/maxTotalWeeks for ${t}`
        : undefined,
    );
    if (minMatch && maxMatch) {
      const lo = Number(minMatch[1]);
      const hi = Number(maxMatch[1]);
      pushResult(
        `spec ${t} range is ascending`,
        hi > lo,
        hi > lo
          ? undefined
          : `inverted range min=${lo} max=${hi} for ${t}`,
      );
    }
  }

  pushResult(
    "RACE_TARGETS array exported",
    /export\s+const\s+RACE_TARGETS\s*:/.test(src),
    undefined,
  );
  pushResult(
    "ATHLETE_LEVELS array exported",
    /export\s+const\s+ATHLETE_LEVELS\s*:/.test(src),
    undefined,
  );
}

const generatorFile = readOr(GENERATOR_PATH, "generator file present");
if (generatorFile.present && generatorFile.content) {
  const src = generatorFile.content;
  pushResult("generator file present", true);
  pushResult(
    "generatePeriodization exported",
    /export\s+function\s+generatePeriodization\b/.test(src),
  );
  pushResult(
    "assertPeriodizationPlanValid exported",
    /export\s+function\s+assertPeriodizationPlanValid\b/.test(src),
  );
  pushResult(
    "PeriodizationInputError exported",
    /export\s+class\s+PeriodizationInputError\b/.test(src),
  );
  for (const cycle of REQUIRED_CYCLES) {
    pushResult(
      `generator emits "${cycle}" block`,
      new RegExp(`cycleType:\\s*"${cycle}"`).test(src),
    );
  }
  pushResult(
    "validator enforces first-block = base",
    /FIRST_BLOCK_NOT_BASE/.test(src),
  );
  pushResult(
    "validator enforces last-block = taper",
    /LAST_BLOCK_NOT_TAPER/.test(src),
  );
  pushResult(
    "validator detects skipped weeks",
    /WEEKS_NOT_CONTIGUOUS/.test(src),
  );
  pushResult(
    "validator rejects non-positive volume",
    /NONPOSITIVE_VOLUME/.test(src),
  );
}

const routeFile = readOr(ROUTE_PATH, "wizard route present");
if (routeFile.present && routeFile.content) {
  const src = routeFile.content;
  pushResult("wizard route present", true);
  pushResult(
    "wizard route gates on supabase.auth.getUser()",
    /supabase\.auth\.getUser\(\)/.test(src),
  );
  pushResult(
    "wizard route imports generator",
    /generatePeriodization/.test(src),
  );
  pushResult(
    "wizard route maps PeriodizationInputError to apiValidationFailed",
    /PeriodizationInputError/.test(src)
      && /apiValidationFailed/.test(src),
  );
}

const runbookFile = readOr(RUNBOOK_PATH, "runbook present");
if (runbookFile.present && runbookFile.content) {
  const src = runbookFile.content;
  pushResult("runbook present", true);
  pushResult(
    "runbook cross-links check-periodization-template",
    src.includes("check-periodization-template"),
  );
  pushResult("runbook cross-links L23-06", src.includes("L23-06"));
}

function extractRaceSpecBlock(src: string, name: string): string | null {
  const idx = src.indexOf(`${name}:`);
  if (idx < 0) return null;
  let depth = 0;
  let started = false;
  for (let i = idx; i < src.length; i += 1) {
    const ch = src[i];
    if (ch === "{") {
      depth += 1;
      started = true;
    } else if (ch === "}") {
      depth -= 1;
      if (started && depth === 0) {
        return src.slice(idx, i + 1);
      }
    }
  }
  return null;
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
  `\n${results.length - failed}/${results.length} periodization checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL23-06 invariants broken. See docs/runbooks/PERIODIZATION_WIZARD_RUNBOOK.md.",
  );
  process.exit(1);
}
