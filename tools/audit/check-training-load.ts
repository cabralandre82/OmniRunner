/**
 * check-training-load.ts
 *
 * L21-04 — CI guard for the training-load pure-domain
 * module (TSS / IF / CTL / ATL / TSB + zone classifier).
 *
 * Enforces:
 *   - Purity (no IO imports, no Date.now inside math files),
 *   - Canonical time constants (τ_CTL = 42, τ_ATL = 7),
 *   - Session TSS methods (rTSS, hrTSS, fallback),
 *   - Zone-band classifier with the 5 canonical bands,
 *   - Unit-test coverage for all the above.
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

const dir = "portal/src/lib/training-load";
const types   = safeRead(resolve(ROOT, `${dir}/types.ts`),   "types.ts present");
const tss     = safeRead(resolve(ROOT, `${dir}/tss.ts`),     "tss.ts present");
const rolling = safeRead(resolve(ROOT, `${dir}/rolling.ts`), "rolling.ts present");
const idx     = safeRead(resolve(ROOT, `${dir}/index.ts`),   "index.ts present");
const tssTest = safeRead(resolve(ROOT, `${dir}/tss.test.ts`),     "tss.test.ts present");
const rollTest = safeRead(resolve(ROOT, `${dir}/rolling.test.ts`), "rolling.test.ts present");

if (types) {
  push(
    "types: canonical CTL time constant = 42 days",
    /CTL_TAU_DAYS = 42/.test(types),
  );
  push(
    "types: canonical ATL time constant = 7 days",
    /ATL_TAU_DAYS = 7/.test(types),
  );
  push(
    "types: caps per-session TSS at 500",
    /TSS_MAX_PER_SESSION = 500/.test(types),
  );
  push(
    "types: caps IF at 1.3",
    /IF_MAX = 1\.3/.test(types),
  );
  push(
    "types: AthleteThresholds covers HR and run FTP pace",
    /heartRateThresholdBpm/.test(types)
      && /runFtpPaceSecPerKm/.test(types),
  );
  push(
    "types: SessionSample exposes duration + Strava-native fields",
    /durationSec: number/.test(types)
      && /avgHeartRateBpm/.test(types)
      && /normalizedGradedPaceSecPerKm/.test(types),
  );
  push(
    "types: TssBreakdown surfaces method (rTSS / hrTSS / fallback)",
    /method: "rTSS" \| "hrTSS" \| "fallback"/.test(types),
  );
  push(
    "types: DailyLoad rollup shape",
    /tssSum: number/.test(types)
      && /sessionCount: number/.test(types),
  );
  push(
    "types: LoadPoint carries ctl + atl + tsb + dailyTss",
    /ctl: number/.test(types)
      && /atl: number/.test(types)
      && /tsb: number/.test(types)
      && /dailyTss: number/.test(types),
  );
  push(
    "types: TRAINING_ZONE_BANDS covers all 5 zones",
    /"rest"/.test(types)
      && /"optimal"/.test(types)
      && /"productive"/.test(types)
      && /"overreaching"/.test(types)
      && /"high_risk"/.test(types),
  );
  push(
    "types: high_risk band lower bound = -Infinity, rest band upper bound = +Infinity",
    /tsbMin: Number\.NEGATIVE_INFINITY/.test(types)
      && /tsbMax: Number\.POSITIVE_INFINITY/.test(types),
  );
}

if (tss) {
  push(
    "tss: pure (no node:fs / node:http / node:net imports)",
    !/from ["']node:(fs|http|net|child_process)["']/.test(tss),
  );
  push(
    "tss: does not read Date.now (pure function)",
    !/Date\.now\(\)/.test(tss),
  );
  push(
    "tss: exports computeSessionTss",
    /export function computeSessionTss\b/.test(tss),
  );
  push(
    "tss: exports clampIf + clampTss + hrIntensityFactor",
    /export function clampIf\b/.test(tss)
      && /export function clampTss\b/.test(tss)
      && /export function hrIntensityFactor\b/.test(tss),
  );
  push(
    "tss: returns zero when durationSec <= 0",
    /durationSec <= 0[\s\S]{0,300}tss: 0/.test(tss),
  );
  push(
    "tss: rTSS path prefers NGP + runFtpPaceSecPerKm",
    /normalizedGradedPaceSecPerKm[\s\S]{0,200}runFtpPaceSecPerKm/.test(tss)
      && /method: "rTSS"/.test(tss),
  );
  push(
    "tss: hrTSS path uses avgHeartRateBpm + heartRateThresholdBpm",
    /avgHeartRateBpm[\s\S]{0,200}heartRateThresholdBpm/.test(tss)
      && /method: "hrTSS"/.test(tss),
  );
  push(
    "tss: fallback path defaults IF to 0.70",
    /intensityFactor = 0\.70/.test(tss)
      && /method: "fallback"/.test(tss),
  );
  push(
    "tss: TSS formula is hours * IF^2 * 100",
    /hours \* intensityFactor \* intensityFactor \* 100/.test(tss),
  );
  push(
    "tss: clampIf rejects NaN / negative",
    /!Number\.isFinite\(intensityFactor\)[\s\S]{0,200}intensityFactor < 0/.test(tss),
  );
  push(
    "tss: clampTss bounded by TSS_MAX_PER_SESSION",
    /Math\.min\(tss, TSS_MAX_PER_SESSION\)/.test(tss),
  );
  push(
    "tss: hrIntensityFactor returns 0 for non-positive ratios",
    /ratio <= 0[\s\S]{0,100}return 0/.test(tss),
  );
  push(
    "tss: hrIntensityFactor normalises to IF = 1 at ratio = 1",
    /0\.5 \* ratio \+ 0\.5 \* ratio \* ratio/.test(tss),
  );
}

if (rolling) {
  push(
    "rolling: pure (no node:fs / node:http / node:net imports)",
    !/from ["']node:(fs|http|net|child_process)["']/.test(rolling),
  );
  push(
    "rolling: does not read Date.now (pure function)",
    !/Date\.now\(\)/.test(rolling),
  );
  push(
    "rolling: exports rollupDailyTss",
    /export function rollupDailyTss\b/.test(rolling),
  );
  push(
    "rolling: exports buildLoadSeries",
    /export function buildLoadSeries\b/.test(rolling),
  );
  push(
    "rolling: exports classifyTrainingZone",
    /export function classifyTrainingZone\b/.test(rolling),
  );
  push(
    "rolling: exports computeCtlRampRate",
    /export function computeCtlRampRate\b/.test(rolling),
  );
  push(
    "rolling: exports sessionsToSeries end-to-end helper",
    /export function sessionsToSeries\b/.test(rolling),
  );
  push(
    "rolling: CTL recurrence uses (tss - ctl) / tau",
    /ctl \+ \(dailyTss - ctl\) \/ ctlTau/.test(rolling),
  );
  push(
    "rolling: ATL recurrence uses (tss - atl) / tau",
    /atl \+ \(dailyTss - atl\) \/ atlTau/.test(rolling),
  );
  push(
    "rolling: TSB = CTL - ATL",
    /tsb: roundDecimals\(ctl - atl, 1\)/.test(rolling),
  );
  push(
    "rolling: defaults time constants from types module (42/7)",
    /CTL_TAU_DAYS/.test(rolling) && /ATL_TAU_DAYS/.test(rolling),
  );
  push(
    "rolling: rejects non-positive time constants",
    /ctlTau <= 0 \|\| atlTau <= 0[\s\S]{0,200}throw new Error/.test(rolling),
  );
  push(
    "rolling: rejects inverted date ranges",
    /"'to' must be >= 'from'"/.test(rolling),
  );
  push(
    "rolling: honours timezone offset (minutes)",
    /timezoneOffsetMinutes/.test(rolling)
      && /\* 60_000/.test(rolling),
  );
  push(
    "rolling: day keys are ISO YYYY-MM-DD",
    /YYYY-MM-DD/.test(rolling)
      || /\^\(\\d\{4\}\)-\(\\d\{2\}\)-\(\\d\{2\}\)\$/.test(rolling),
  );
  push(
    "rolling: classifyTrainingZone iterates over TRAINING_ZONE_BANDS",
    /for \(const band of TRAINING_ZONE_BANDS\)/.test(rolling),
  );
  push(
    "rolling: computeCtlRampRate short-circuits when series too short",
    /series\.length < window \+ 1[\s\S]{0,100}return 0/.test(rolling),
  );
}

if (idx) {
  push(
    "index re-exports types + tss + rolling",
    /from "\.\/types"/.test(idx)
      && /from "\.\/tss"/.test(idx)
      && /from "\.\/rolling"/.test(idx),
  );
}

if (tssTest) {
  push(
    "tss.test: covers 1h@threshold → TSS 100 (rTSS)",
    /rTSS: 1-hour at threshold pace yields TSS 100/.test(tssTest),
  );
  push(
    "tss.test: covers hrTSS path",
    /hrTSS: threshold HR for one hour yields TSS 100/.test(tssTest),
  );
  push(
    "tss.test: covers fallback path",
    /falls back to IF 0\.70/.test(tssTest),
  );
  push(
    "tss.test: verifies clamp IF / TSS bounds",
    /clamps pathologically high IF/.test(tssTest)
      && /clamps pathologically high TSS/.test(tssTest),
  );
  push(
    "tss.test: prefers rTSS when both pace and HR are available",
    /prefers rTSS when both pace and HR are available/.test(tssTest),
  );
  push(
    "tss.test: hrIntensityFactor monotonicity asserted",
    /hrIntensityFactor monotonically increasing/.test(tssTest),
  );
}

if (rollTest) {
  push(
    "rolling.test: daily rollup aggregates and filters",
    /aggregates TSS per day/.test(rollTest),
  );
  push(
    "rolling.test: CTL/ATL convergence asserted",
    /CTL and ATL converge monotonically/.test(rollTest),
  );
  push(
    "rolling.test: TSB = CTL - ATL invariant",
    /TSB is CTL minus ATL/.test(rollTest),
  );
  push(
    "rolling.test: seed CTL/ATL respected",
    /honours seed CTL\/ATL values/.test(rollTest),
  );
  push(
    "rolling.test: rejects non-positive tau",
    /rejects non-positive time constants/.test(rollTest),
  );
  push(
    "rolling.test: rejects inverted ranges",
    /rejects inverted date ranges/.test(rollTest),
  );
  push(
    "rolling.test: zone classifier covers all 5 bands",
    /high_risk/.test(rollTest)
      && /overreaching/.test(rollTest)
      && /productive/.test(rollTest)
      && /optimal/.test(rollTest)
      && /rest/.test(rollTest),
  );
  push(
    "rolling.test: ramp rate short-circuit asserted",
    /returns 0 ramp when series is too short/.test(rollTest),
  );
  push(
    "rolling.test: end-to-end sessionsToSeries wiring asserted",
    /end-to-end: sessionsToSeries wires rollup and series/.test(rollTest),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L21-04-ausencia-de-training-load-tss-ctl-atl.md",
);
const finding = safeRead(findingPath, "L21-04 finding present");
if (finding) {
  push(
    "finding references training-load module",
    /portal\/src\/lib\/training-load/.test(finding),
  );
  push(
    "finding references CTL + ATL + TSB primitives",
    /CTL_TAU_DAYS/.test(finding)
      || /buildLoadSeries/.test(finding)
      || /classifyTrainingZone/.test(finding),
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
  `\n${results.length - failed}/${results.length} training-load checks passed.`,
);
if (failed > 0) {
  console.error("\nL21-04 invariants broken.");
  process.exit(1);
}
