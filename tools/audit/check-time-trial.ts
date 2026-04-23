/**
 * check-time-trial.ts
 *
 * L23-14 — CI guard for the time-trial protocol + threshold estimator
 * + scheduler pipeline.
 *
 * Fails closed if:
 *
 *   1. `TimeTrialProtocol` loses any of the 3 canonical protocols
 *      (threeKm / fiveKm / thirtyMinute).
 *   2. Any protocol's `pacingMultiplier` drops below 1.00 — a TT is
 *      by definition run at ≥ threshold pace, so a multiplier < 1
 *      would produce an impossible threshold pace.
 *   3. Estimator stops branching on protocol multipliers.
 *   4. Scheduler stops pinning `cycle_type = 'test'` or quantising
 *      to UTC calendar day.
 *   5. Runbook is missing or no longer cross-links the guard.
 *
 * Usage:
 *   npm run audit:time-trial
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const PROTOCOL_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/value_objects/time_trial_protocol.dart",
);
const RESULT_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/entities/time_trial_result_entity.dart",
);
const ESTIMATOR_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/time_trial_threshold_estimator.dart",
);
const SCHEDULER_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/time_trial_scheduler.dart",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/TIME_TRIAL_RUNBOOK.md",
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

const protocol = safeRead(PROTOCOL_PATH, "time_trial_protocol.dart present");
if (protocol) {
  push("time_trial_protocol.dart present", true);

  push(
    "enum TimeTrialProtocol declared",
    /enum\s+TimeTrialProtocol\b/.test(protocol),
  );

  for (const kind of ["threeKm", "fiveKm", "thirtyMinute"]) {
    push(
      `TimeTrialProtocol.${kind} declared`,
      new RegExp(`\\b${kind}\\s*\\(`).test(protocol),
    );
  }

  for (const kindStr of ["three_km", "five_km", "thirty_minute"]) {
    push(
      `protocol ${kindStr} kind pinned`,
      new RegExp(`kind:\\s*'${kindStr}'`).test(protocol),
    );
  }

  const multiplierMatches = protocol.matchAll(
    /pacingMultiplier:\s*([0-9.]+)/g,
  );
  let allAboveOne = true;
  let count = 0;
  for (const m of multiplierMatches) {
    count += 1;
    if (parseFloat(m[1]) < 1.0) allAboveOne = false;
  }
  push(
    "every pacingMultiplier ≥ 1.00 (3 protocols)",
    count === 3 && allAboveOne,
    count !== 3 ? `expected 3 multipliers, found ${count}` : undefined,
  );

  push(
    "thirtyMinute pacingMultiplier == 1.00",
    /thirtyMinute[\s\S]{0,300}pacingMultiplier:\s*1\.00/.test(protocol),
  );
  push(
    "TimeTrialFreshness.maxAgeDays == 84",
    /static\s+const\s+int\s+maxAgeDays\s*=\s*84\s*;/.test(protocol),
  );
  push(
    "TimeTrialProtocol.fromKind declared",
    /static\s+TimeTrialProtocol\?\s+fromKind\s*\(/.test(protocol),
  );
}

const resultFile = safeRead(
  RESULT_PATH,
  "time_trial_result_entity.dart present",
);
if (resultFile) {
  push("time_trial_result_entity.dart present", true);
  push(
    "TimeTrialResultEntity class declared",
    /class\s+TimeTrialResultEntity\b/.test(resultFile),
  );
  push(
    "entity exposes avgPaceSecKm getter",
    /avgPaceSecKm/.test(resultFile),
  );
  push(
    "entity exposes isFreshOn method",
    /isFreshOn\s*\(/.test(resultFile),
  );
  push(
    "entity is pure (no flutter imports)",
    !/import\s+['"]package:flutter\//.test(resultFile),
  );
}

const estimator = safeRead(
  ESTIMATOR_PATH,
  "time_trial_threshold_estimator.dart present",
);
if (estimator) {
  push("time_trial_threshold_estimator.dart present", true);
  push(
    "TimeTrialThresholdEstimator class declared",
    /class\s+TimeTrialThresholdEstimator\b/.test(estimator),
  );
  push(
    "TimeTrialEstimate class declared",
    /class\s+TimeTrialEstimate\b/.test(estimator),
  );
  push(
    "estimator reads pacingMultiplier from protocol",
    /protocol\.pacingMultiplier/.test(estimator),
  );
  push(
    "estimator reads hrMultiplier from protocol",
    /protocol\.hrMultiplier/.test(estimator),
  );
  push(
    "estimator returns invalid on corrupt input (distance ≤ 0)",
    /actualDistanceM\s*<=?\s*0/.test(estimator)
      && /TimeTrialEstimate\.invalid/.test(estimator),
  );
  push(
    "estimator is pure (no flutter imports)",
    !/import\s+['"]package:flutter\//.test(estimator)
      && !/import\s+['"]dart:io['"]/.test(estimator),
  );
}

const scheduler = safeRead(
  SCHEDULER_PATH,
  "time_trial_scheduler.dart present",
);
if (scheduler) {
  push("time_trial_scheduler.dart present", true);
  push(
    "TimeTrialScheduler class declared",
    /class\s+TimeTrialScheduler\b/.test(scheduler),
  );
  push(
    "TimeTrialScheduledWorkout class declared",
    /class\s+TimeTrialScheduledWorkout\b/.test(scheduler),
  );
  push(
    "scheduler pins cycleType = 'test'",
    /cycleType:\s*['"]test['"]/.test(scheduler),
  );
  push(
    "scheduler quantises to UTC day",
    /DateTime\.utc\s*\(/.test(scheduler) && /toUtc\s*\(\s*\)/.test(scheduler),
  );
  push(
    "scheduler rejects empty planId",
    /ArgumentError/.test(scheduler) && /planId/.test(scheduler),
  );
  push(
    "payload carries time_trial_kind",
    /'time_trial_kind'/.test(scheduler),
  );
  push(
    "scheduler is pure (no flutter imports)",
    !/import\s+['"]package:flutter\//.test(scheduler),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:time-trial",
    runbook.includes("audit:time-trial") || runbook.includes("check-time-trial"),
  );
  push("runbook cross-links L23-14", runbook.includes("L23-14"));
  push(
    "runbook references L21-05 dependency",
    runbook.includes("L21-05"),
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
  `\n${results.length - failed}/${results.length} time-trial checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL23-14 invariants broken. See docs/runbooks/TIME_TRIAL_RUNBOOK.md.",
  );
  process.exit(1);
}
