/**
 * check-athlete-onboarding.ts
 *
 * L23-12 — CI guard for the athlete onboarding state-machine.
 *
 * Fails closed if any of the following drift:
 *
 *   1. `AthleteOnboardingStep` loses any of its 6 canonical values
 *      (invited / joined / profileCompleted / stravaChoiceMade /
 *      zonesReady / completed) — every consumer (coach dashboard,
 *      wizard, email runner) switches on these.
 *   2. Wire strings move away from the published contract
 *      (`invited` / `joined` / `profile_completed` /
 *      `strava_choice_made` / `zones_ready` / `completed`) — these
 *      are persistence values and analytics event keys.
 *   3. `AthleteOnboardingBounds.staleInviteDays` != 14 or
 *      `stalledProfileDays` != 3. Bounds are content and must be
 *      changed with docs.
 *   4. `StravaImportChoice` loses `undecided` / `imported` /
 *      `skipped` or their wire strings.
 *   5. `AthleteOnboardingService` stops being pure (imports
 *      `dart:io` or `package:flutter/`).
 *   6. Service drops any of the transition methods or the nudge
 *      resolver — forgetting one would silently disable a UX step.
 *   7. Runbook is missing or no longer cross-links the guard and
 *      finding.
 *
 * Usage:
 *   npm run audit:athlete-onboarding
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const STEP_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/value_objects/athlete_onboarding_step.dart",
);
const STATE_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/entities/athlete_onboarding_state.dart",
);
const SERVICE_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/athlete_onboarding_service.dart",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/ATHLETE_ONBOARDING_RUNBOOK.md",
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

const step = safeRead(STEP_PATH, "athlete_onboarding_step.dart present");
if (step) {
  push("athlete_onboarding_step.dart present", true);

  push(
    "enum AthleteOnboardingStep declared",
    /enum\s+AthleteOnboardingStep\b/.test(step),
  );
  for (const v of [
    "invited",
    "joined",
    "profileCompleted",
    "stravaChoiceMade",
    "zonesReady",
    "completed",
  ]) {
    push(
      `AthleteOnboardingStep.${v} declared`,
      new RegExp(`\\b${v}\\b`).test(step),
    );
  }

  const wireStrings = [
    "invited",
    "joined",
    "profile_completed",
    "strava_choice_made",
    "zones_ready",
    "completed",
  ];
  for (const w of wireStrings) {
    push(
      `wire string '${w}' present`,
      new RegExp(`'${w}'`).test(step),
    );
  }

  push(
    "athleteOnboardingStepFromWire resolver present",
    /athleteOnboardingStepFromWire\s*\(/.test(step),
  );

  push(
    "AthleteOnboardingBounds.staleInviteDays == 14",
    /static\s+const\s+int\s+staleInviteDays\s*=\s*14\s*;/.test(step),
  );
  push(
    "AthleteOnboardingBounds.stalledProfileDays == 3",
    /static\s+const\s+int\s+stalledProfileDays\s*=\s*3\s*;/.test(step),
  );

  push(
    "step file is pure (no dart:io / flutter imports)",
    !/import\s+['"]dart:io['"]/.test(step)
      && !/import\s+['"]package:flutter\//.test(step),
  );
}

const state = safeRead(
  STATE_PATH,
  "athlete_onboarding_state.dart present",
);
if (state) {
  push("athlete_onboarding_state.dart present", true);

  push(
    "enum StravaImportChoice declared",
    /enum\s+StravaImportChoice\b/.test(state),
  );
  for (const v of ["undecided", "imported", "skipped"]) {
    push(
      `StravaImportChoice.${v} declared`,
      new RegExp(`\\b${v}\\b`).test(state),
    );
    push(
      `StravaImportChoice wire '${v}' present`,
      new RegExp(`'${v}'`).test(state),
    );
  }

  push(
    "AthleteOnboardingState class declared",
    /class\s+AthleteOnboardingState\b/.test(state),
  );
  push(
    "AthleteOnboardingState.initial factory present",
    /factory\s+AthleteOnboardingState\.initial\s*\(/.test(state),
  );
  push(
    "AthleteOnboardingState.copyWith present",
    /AthleteOnboardingState\s+copyWith\s*\(/.test(state),
  );
  push(
    "state file is pure (no dart:io / flutter imports)",
    !/import\s+['"]dart:io['"]/.test(state)
      && !/import\s+['"]package:flutter\//.test(state),
  );
}

const svc = safeRead(SERVICE_PATH, "athlete_onboarding_service.dart present");
if (svc) {
  push("athlete_onboarding_service.dart present", true);

  push(
    "AthleteOnboardingService class declared",
    /class\s+AthleteOnboardingService\b/.test(svc),
  );
  push(
    "AthleteOnboardingTransitionError class declared",
    /class\s+AthleteOnboardingTransitionError\b/.test(svc),
  );
  push(
    "AthleteOnboardingNudge enum declared",
    /enum\s+AthleteOnboardingNudge\b/.test(svc),
  );

  for (const n of [
    "none",
    "staleInvite",
    "profileStalled",
    "stravaChoiceRequired",
    "zonesMissing",
    "readyForFirstPlan",
  ]) {
    push(
      `AthleteOnboardingNudge.${n} declared`,
      new RegExp(`\\b${n}\\b`).test(svc),
    );
  }

  for (const m of [
    "invite",
    "markJoined",
    "markProfileCompleted",
    "markStravaChoice",
    "markZonesReady",
    "markCompleted",
    "nextStep",
    "nudgeFor",
  ]) {
    push(
      `service exposes ${m}(...)`,
      new RegExp(`\\b${m}\\s*\\(`).test(svc),
    );
  }

  push(
    "markStravaChoice rejects undecided",
    /StravaImportChoice\.undecided[\s\S]{0,200}throw/.test(svc),
  );
  push(
    "nudgeFor reads staleInviteDays",
    /AthleteOnboardingBounds\.staleInviteDays/.test(svc),
  );
  push(
    "nudgeFor reads stalledProfileDays",
    /AthleteOnboardingBounds\.stalledProfileDays/.test(svc),
  );

  push(
    "service is pure (no dart:io / flutter imports)",
    !/import\s+['"]dart:io['"]/.test(svc)
      && !/import\s+['"]package:flutter\//.test(svc),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:athlete-onboarding",
    runbook.includes("audit:athlete-onboarding")
      || runbook.includes("check-athlete-onboarding"),
  );
  push("runbook cross-links L23-12", runbook.includes("L23-12"));
  push(
    "runbook mentions Strava import choice",
    /strava/i.test(runbook),
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
  `\n${results.length - failed}/${results.length} athlete-onboarding checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL23-12 invariants broken. See docs/runbooks/ATHLETE_ONBOARDING_RUNBOOK.md.",
  );
  process.exit(1);
}
