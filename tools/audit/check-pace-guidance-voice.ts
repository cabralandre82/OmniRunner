/**
 * check-pace-guidance-voice.ts
 *
 * L22-04 — CI guard for the real-time pace-guidance voice trigger.
 *
 * Fails closed if any of the following drift:
 *
 *   1. `PaceGuidanceState` loses any of its 3 canonical values
 *      (onTarget / tooFast / tooSlow) — the AudioCueFormatter
 *      catalogue branches on those wire strings.
 *   2. The snake_case wire strings move away from the published
 *      contract (`on_target` / `too_fast` / `too_slow`).
 *   3. `PaceGuidanceVoiceTrigger` stops reading a target pace band
 *      (targetPaceMinSecPerKm / targetPaceMaxSecPerKm) — the finding
 *      is explicitly about comparing *live* pace vs *prescribed*
 *      pace, not about per-km announcements.
 *   4. Trigger loses hysteresis (`confirmCount`) or cooldown
 *      (`cooldownMs`) — without them the TTS fires every tick.
 *   5. Trigger emits something other than `AudioEventType.paceAlert`.
 *   6. File becomes non-pure (imports `dart:io` or
 *      `package:flutter/`) — domain layer must stay platform-free.
 *   7. Runbook is missing or no longer cross-links the guard and
 *      finding.
 *
 * Usage:
 *   npm run audit:pace-guidance
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const TRIGGER_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/usecases/pace_guidance_voice_trigger.dart",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/PACE_GUIDANCE_RUNBOOK.md",
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

const trigger = safeRead(
  TRIGGER_PATH,
  "pace_guidance_voice_trigger.dart present",
);
if (trigger) {
  push("pace_guidance_voice_trigger.dart present", true);

  push(
    "enum PaceGuidanceState declared",
    /enum\s+PaceGuidanceState\b/.test(trigger),
  );
  for (const v of ["onTarget", "tooFast", "tooSlow"]) {
    push(
      `PaceGuidanceState.${v} declared`,
      new RegExp(`\\b${v}\\b`).test(trigger),
    );
  }

  push(
    "wire string 'on_target' present",
    /'on_target'/.test(trigger),
  );
  push(
    "wire string 'too_fast' present",
    /'too_fast'/.test(trigger),
  );
  push(
    "wire string 'too_slow' present",
    /'too_slow'/.test(trigger),
  );

  push(
    "class PaceGuidanceVoiceTrigger declared",
    /class\s+PaceGuidanceVoiceTrigger\b/.test(trigger),
  );

  push(
    "evaluate(...) reads currentPaceSecPerKm",
    /currentPaceSecPerKm/.test(trigger),
  );
  push(
    "evaluate(...) reads targetPaceMinSecPerKm",
    /targetPaceMinSecPerKm/.test(trigger),
  );
  push(
    "evaluate(...) reads targetPaceMaxSecPerKm",
    /targetPaceMaxSecPerKm/.test(trigger),
  );
  push(
    "evaluate(...) takes a timestampMs argument",
    /timestampMs/.test(trigger),
  );

  push(
    "hysteresis: confirmCount parameter declared",
    /\bconfirmCount\b/.test(trigger),
  );
  push(
    "cooldown: cooldownMs parameter declared",
    /\bcooldownMs\b/.test(trigger),
  );
  push(
    "deadband: deadbandSec parameter declared",
    /\bdeadbandSec\b/.test(trigger),
  );

  push(
    "emits AudioEventType.paceAlert",
    /AudioEventType\.paceAlert/.test(trigger),
  );
  push(
    "payload includes 'state' key",
    /'state'\s*:/.test(trigger),
  );
  push(
    "payload includes 'deviationSec' key",
    /'deviationSec'\s*:/.test(trigger),
  );
  push(
    "payload echoes 'targetMinSecPerKm' and 'targetMaxSecPerKm'",
    /'targetMinSecPerKm'/.test(trigger)
      && /'targetMaxSecPerKm'/.test(trigger),
  );

  push(
    "NaN/infinite/non-positive pace guarded",
    /isNaN/.test(trigger)
      && /isInfinite/.test(trigger)
      && /pace\s*<=\s*0/.test(trigger),
  );
  push(
    "inverted target band is silenced",
    /targetPaceMinSecPerKm\s*>\s*targetPaceMaxSecPerKm/.test(trigger),
  );

  push(
    "reset() method present",
    /void\s+reset\s*\(\s*\)/.test(trigger),
  );

  push(
    "trigger is pure (no dart:io / flutter imports)",
    !/import\s+['"]dart:io['"]/.test(trigger)
      && !/import\s+['"]package:flutter\//.test(trigger),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:pace-guidance",
    runbook.includes("audit:pace-guidance")
      || runbook.includes("check-pace-guidance-voice"),
  );
  push("runbook cross-links L22-04", runbook.includes("L22-04"));
  push(
    "runbook mentions target-band comparison",
    /target\s+pace/i.test(runbook) || /banda\s+alvo/i.test(runbook),
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
  `\n${results.length - failed}/${results.length} pace-guidance checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL22-04 invariants broken. See docs/runbooks/PACE_GUIDANCE_RUNBOOK.md.",
  );
  process.exit(1);
}
