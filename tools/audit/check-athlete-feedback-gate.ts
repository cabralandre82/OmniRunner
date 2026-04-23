/**
 * check-athlete-feedback-gate.ts
 *
 * L23-13 — CI guard for the athlete workout-feedback gate.
 *
 * Fails closed if:
 *
 *   1. `WorkoutCompletionStatus` loses any of its 3 canonical values
 *      (pending / partial / complete) — callers do switch matches.
 *   2. `WorkoutFeedbackBounds` loses the RPE/mood ranges or the
 *      `bronzeStreakDays = 30` constant.
 *   3. `WorkoutFeedbackEvaluator` stops referencing RPE + mood as
 *      required fields (finding's explicit contract).
 *   4. `FeedbackStreakCalculator` stops quantising to UTC calendar
 *      day or stops reading `bronzeStreakDays`.
 *   5. Runbook is missing or no longer cross-links the guard.
 *
 * Usage:
 *   npm run audit:athlete-feedback-gate
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const STATUS_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/value_objects/workout_completion_status.dart",
);
const EVALUATOR_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/workout_feedback_evaluator.dart",
);
const STREAK_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/feedback_streak_calculator.dart",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/ATHLETE_FEEDBACK_GATE_RUNBOOK.md",
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

const status = safeRead(STATUS_PATH, "workout_completion_status.dart present");
if (status) {
  push("workout_completion_status.dart present", true);

  push(
    "enum WorkoutCompletionStatus declared",
    /enum\s+WorkoutCompletionStatus\b/.test(status),
  );
  for (const v of ["pending", "partial", "complete"]) {
    push(
      `WorkoutCompletionStatus.${v} declared`,
      new RegExp(`\\b${v}\\b`).test(status),
    );
  }

  push(
    "class WorkoutFeedbackBounds declared",
    /class\s+WorkoutFeedbackBounds\b/.test(status),
  );
  push(
    "WorkoutFeedbackBounds.rpeMin == 1",
    /static\s+const\s+int\s+rpeMin\s*=\s*1\s*;/.test(status),
  );
  push(
    "WorkoutFeedbackBounds.rpeMax == 10",
    /static\s+const\s+int\s+rpeMax\s*=\s*10\s*;/.test(status),
  );
  push(
    "WorkoutFeedbackBounds.moodMin == 1",
    /static\s+const\s+int\s+moodMin\s*=\s*1\s*;/.test(status),
  );
  push(
    "WorkoutFeedbackBounds.moodMax == 5",
    /static\s+const\s+int\s+moodMax\s*=\s*5\s*;/.test(status),
  );
  push(
    "WorkoutFeedbackBounds.bronzeStreakDays == 30",
    /static\s+const\s+int\s+bronzeStreakDays\s*=\s*30\s*;/.test(status),
  );
}

const evaluator = safeRead(
  EVALUATOR_PATH,
  "workout_feedback_evaluator.dart present",
);
if (evaluator) {
  push("workout_feedback_evaluator.dart present", true);

  push(
    "WorkoutFeedbackEvaluator class declared",
    /class\s+WorkoutFeedbackEvaluator\b/.test(evaluator),
  );
  push(
    "evaluator reads perceivedEffort (RPE)",
    /perceivedEffort/.test(evaluator),
  );
  push(
    "evaluator reads mood",
    /\.mood\b/.test(evaluator),
  );
  push(
    "evaluator enforces WorkoutFeedbackBounds",
    /WorkoutFeedbackBounds\.rpeMin/.test(evaluator)
      && /WorkoutFeedbackBounds\.rpeMax/.test(evaluator)
      && /WorkoutFeedbackBounds\.moodMin/.test(evaluator)
      && /WorkoutFeedbackBounds\.moodMax/.test(evaluator),
  );
  push(
    "evaluator returns WorkoutCompletionStatus.complete path",
    /WorkoutCompletionStatus\.complete/.test(evaluator),
  );
  push(
    "evaluator returns WorkoutCompletionStatus.partial path",
    /WorkoutCompletionStatus\.partial/.test(evaluator),
  );
  push(
    "evaluator returns WorkoutCompletionStatus.pending when completed null",
    /completed\s*==\s*null/.test(evaluator)
      && /WorkoutCompletionStatus\.pending/.test(evaluator),
  );
  push(
    "enum WorkoutFeedbackMissingField covers rpe + mood",
    /enum\s+WorkoutFeedbackMissingField[\s\S]{0,200}\brpe\b[\s\S]{0,200}\bmood\b/i
      .test(evaluator),
  );
  push(
    "evaluator is pure (no imports of dart:io or flutter)",
    !/import\s+['"]dart:io['"]/.test(evaluator)
      && !/import\s+['"]package:flutter\//.test(evaluator),
  );
}

const streak = safeRead(STREAK_PATH, "feedback_streak_calculator.dart present");
if (streak) {
  push("feedback_streak_calculator.dart present", true);

  push(
    "FeedbackStreakResult class declared",
    /class\s+FeedbackStreakResult\b/.test(streak),
  );
  push(
    "FeedbackStreakCalculator class declared",
    /class\s+FeedbackStreakCalculator\b/.test(streak),
  );
  push(
    "calculator reads bronzeStreakDays from bounds",
    /WorkoutFeedbackBounds\.bronzeStreakDays/.test(streak),
  );
  push(
    "calculator quantises to UTC day",
    /DateTime\.utc\s*\(/.test(streak) && /toUtc\s*\(\s*\)/.test(streak),
  );
  push(
    "calculator handles empty input",
    /isEmpty/.test(streak),
  );
  push(
    "calculator is pure (no flutter imports)",
    !/import\s+['"]package:flutter\//.test(streak),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:athlete-feedback-gate",
    runbook.includes("audit:athlete-feedback-gate")
      || runbook.includes("check-athlete-feedback-gate"),
  );
  push("runbook cross-links L23-13", runbook.includes("L23-13"));
  push("runbook mentions 30-day bronze", /30[-\s]day|30\s*dias/.test(runbook));
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
  `\n${results.length - failed}/${results.length} athlete-feedback-gate checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL23-13 invariants broken. See docs/runbooks/ATHLETE_FEEDBACK_GATE_RUNBOOK.md.",
  );
  process.exit(1);
}
