/**
 * check-first-run-onboarding.ts
 *
 * L22-01 — CI guard for the first-run onboarding state
 * machine module.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const dir = "portal/src/lib/first-run-onboarding";
const types   = safeRead(resolve(ROOT, `${dir}/types.ts`),   "types.ts present");
const machine = safeRead(resolve(ROOT, `${dir}/machine.ts`), "machine.ts present");
const resume  = safeRead(resolve(ROOT, `${dir}/resume.ts`),  "resume.ts present");
const idx     = safeRead(resolve(ROOT, `${dir}/index.ts`),   "index.ts present");
const mtest   = safeRead(resolve(ROOT, `${dir}/machine.test.ts`), "machine.test.ts present");
const rtest   = safeRead(resolve(ROOT, `${dir}/resume.test.ts`),  "resume.test.ts present");

if (types) {
  push(
    "types: declares canonical 10 states",
    /"not_started"/.test(types)
      && /"welcome_seen"/.test(types)
      && /"strava_connect_in_progress"/.test(types)
      && /"strava_connected"/.test(types)
      && /"zones_configured"/.test(types)
      && /"first_run_planned"/.test(types)
      && /"first_run_completed"/.test(types)
      && /"celebrated"/.test(types)
      && /"skipped"/.test(types)
      && /"dismissed"/.test(types),
  );
  push(
    "types: declares all event types",
    /"welcome_shown"/.test(types)
      && /"strava_connect_initiated"/.test(types)
      && /"strava_connected"/.test(types)
      && /"strava_connection_failed"/.test(types)
      && /"zones_configured"/.test(types)
      && /"first_run_planned"/.test(types)
      && /"first_run_completed"/.test(types)
      && /"celebration_shown"/.test(types)
      && /"skipped"/.test(types)
      && /"dismissed"/.test(types)
      && /"resumed"/.test(types),
  );
  push(
    "types: strava_connection_failed carries reason payload",
    /strava_connection_failed"; reason: string/.test(types),
  );
  push(
    "types: OnboardingSnapshot carries history + lastUpdatedAt + skipCount",
    /history: ReadonlyArray<OnboardingHistoryEntry>/.test(types)
      && /lastUpdatedAt: number/.test(types)
      && /skipCount: number/.test(types),
  );
  push(
    "types: OnboardingHistoryEntry captures from/to/event/at",
    /from: OnboardingState/.test(types)
      && /to: OnboardingState/.test(types)
      && /event: OnboardingEvent\["type"\]/.test(types)
      && /at: number/.test(types),
  );
  push(
    "types: terminal set covers celebrated + dismissed",
    /TERMINAL_STATES: ReadonlySet<OnboardingState>[\s\S]{0,200}"celebrated"[\s\S]{0,50}"dismissed"/.test(types),
  );
  push(
    "types: STATE_PROGRESS maps not_started → 0 and celebrated → 100",
    /not_started: 0/.test(types) && /celebrated: 100/.test(types),
  );
  push(
    "types: DEFAULT_RESUME_POLICY uses 3d auto-resume + maxAutoResumes 3",
    /autoResumeAfterMs: 3 \* 24 \* 60 \* 60 \* 1000/.test(types)
      && /maxAutoResumes: 3/.test(types),
  );
}

if (machine) {
  push(
    "machine: pure (no fs/http/net imports)",
    !/from ["']node:(fs|http|net|child_process)["']/.test(machine),
  );
  push(
    "machine: does not read Date.now",
    !/Date\.now\(\)/.test(machine),
  );
  push(
    "machine: exports initialSnapshot",
    /export function initialSnapshot\b/.test(machine),
  );
  push(
    "machine: exports reduce",
    /export function reduce\b/.test(machine),
  );
  push(
    "machine: exports progressPercent",
    /export function progressPercent\b/.test(machine),
  );
  push(
    "machine: exports isTerminal",
    /export function isTerminal\b/.test(machine),
  );
  push(
    "machine: exports canTransition",
    /export function canTransition\b/.test(machine),
  );
  push(
    "machine: exports nextActionableState",
    /export function nextActionableState\b/.test(machine),
  );
  push(
    "machine: disallowed events return the snapshot unchanged",
    /if \(!next\)[\s\S]{0,200}return snapshot/.test(machine),
  );
  push(
    "machine: strava_connection_failed rewinds to welcome_seen",
    /strava_connection_failed: "welcome_seen"/.test(machine),
  );
  push(
    "machine: celebrated is terminal (no transitions)",
    /celebrated: \{\}/.test(machine),
  );
  push(
    "machine: dismissed is terminal (no transitions)",
    /dismissed: \{\}/.test(machine),
  );
  push(
    "machine: resume transitions skipped → welcome_seen",
    /skipped: \{[\s\S]{0,200}resumed: "welcome_seen"/.test(machine),
  );
  push(
    "machine: skip increments skipCount",
    /event\.type === "skipped"[\s\S]{0,200}snapshot\.skipCount \+ 1/.test(machine),
  );
  push(
    "machine: celebrated stamps celebratedAt",
    /next === "celebrated"[\s\S]{0,200}snapshot\.celebratedAt \?\? now/.test(machine),
  );
  push(
    "machine: strava_connection_failed stores lastError reason",
    /event\.type === "strava_connection_failed"[\s\S]{0,200}event\.reason/.test(machine),
  );
  push(
    "machine: strava_connect_initiated clears lastError",
    /event\.type === "resumed" \|\| event\.type === "strava_connect_initiated"[\s\S]{0,80}undefined/.test(machine),
  );
  push(
    "machine: history records (at, from, to, event)",
    /at: now, from: snapshot\.state, to: next, event: event\.type/.test(machine),
  );
}

if (resume) {
  push(
    "resume: pure (no Date.now)",
    !/Date\.now\(\)/.test(resume),
  );
  push(
    "resume: exports evaluateResume",
    /export function evaluateResume\b/.test(resume),
  );
  push(
    "resume: terminal snapshots short-circuit with reason 'terminal'",
    /isTerminal\(snapshot\)[\s\S]{0,200}"terminal"/.test(resume),
  );
  push(
    "resume: respects policy.maxAutoResumes",
    /resumeCount >= policy\.maxAutoResumes[\s\S]{0,200}"max_resumes_exhausted"/.test(resume),
  );
  push(
    "resume: non-stallable states return 'not_stalled'",
    /"not_stalled"/.test(resume),
  );
  push(
    "resume: honours policy.autoResumeAfterMs (too_recent)",
    /stalledForMs < policy\.autoResumeAfterMs[\s\S]{0,200}"too_recent"/.test(resume),
  );
  push(
    "resume: counts prior resumed events",
    /entry\.event === "resumed"/.test(resume),
  );
}

if (idx) {
  push(
    "index re-exports types + machine + resume",
    /from "\.\/types"/.test(idx)
      && /from "\.\/machine"/.test(idx)
      && /from "\.\/resume"/.test(idx),
  );
}

if (mtest) {
  push(
    "machine.test: covers full happy path to celebrated",
    /drives the full happy path to celebrated/.test(mtest),
  );
  push(
    "machine.test: covers disallowed events ignored",
    /ignores disallowed events without throwing/.test(mtest),
  );
  push(
    "machine.test: covers failed strava rewind",
    /failed strava connection rewinds to welcome_seen/.test(mtest),
  );
  push(
    "machine.test: covers re-initiate clears error",
    /re-initiating connect clears the stored error/.test(mtest),
  );
  push(
    "machine.test: covers skip increments skipCount",
    /skip increments skipCount/.test(mtest),
  );
  push(
    "machine.test: covers resumed skipped → welcome_seen",
    /resume from skipped returns to welcome_seen/.test(mtest),
  );
  push(
    "machine.test: covers dismissed/celebrated terminality",
    /dismissed is terminal/.test(mtest)
      && /celebrated absorbs further events/.test(mtest),
  );
}

if (rtest) {
  push(
    "resume.test: terminal → no resume",
    /terminal snapshots never trigger resume/.test(rtest),
  );
  push(
    "resume.test: too-recent suppressed",
    /too-recent stalls don't trigger resume/.test(rtest),
  );
  push(
    "resume.test: stalled welcome_seen → resume",
    /stalled welcome_seen → resume/.test(rtest),
  );
  push(
    "resume.test: stalled skipped → resume",
    /stalled skipped → resume/.test(rtest),
  );
  push(
    "resume.test: cap at maxAutoResumes",
    /resume count is capped by policy/.test(rtest),
  );
  push(
    "resume.test: asserts DEFAULT policy constants",
    /DEFAULT_RESUME_POLICY sticks to finding-prescribed values/.test(rtest),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L22-01-onboarding-nao-inclui-primeira-corrida-guiada.md",
);
const finding = safeRead(findingPath, "L22-01 finding present");
if (finding) {
  push(
    "finding references first-run-onboarding module",
    /portal\/src\/lib\/first-run-onboarding/.test(finding),
  );
  push(
    "finding references state machine + resume primitives",
    /DEFAULT_RESUME_POLICY/.test(finding) || /evaluateResume/.test(finding) || /OnboardingState/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} first-run-onboarding checks passed.`,
);
if (failed > 0) {
  console.error("\nL22-01 invariants broken.");
  process.exit(1);
}
