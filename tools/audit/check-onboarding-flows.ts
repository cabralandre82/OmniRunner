/**
 * check-onboarding-flows.ts
 *
 * L07-02 — CI guard for the role-aware onboarding flow primitive.
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

const typesPath = resolve(ROOT, "portal/src/lib/onboarding-flows/types.ts");
const flowsPath = resolve(ROOT, "portal/src/lib/onboarding-flows/flows.ts");
const indexPath = resolve(ROOT, "portal/src/lib/onboarding-flows/index.ts");
const hookPath = resolve(ROOT, "portal/src/components/onboarding/use-onboarding.ts");
const overlayPath = resolve(ROOT, "portal/src/components/onboarding/onboarding-overlay.tsx");
const testPath = resolve(ROOT, "portal/src/lib/onboarding-flows/flows.test.ts");

const types = safeRead(typesPath, "types.ts present");
const flows = safeRead(flowsPath, "flows.ts present");
const index = safeRead(indexPath, "index.ts present");
const hook = safeRead(hookPath, "use-onboarding hook present");
const overlay = safeRead(overlayPath, "onboarding-overlay present");
const tests = safeRead(testPath, "unit tests present");

// ────────────────────────────────────────────────────────────────────────────
// types.ts
// ────────────────────────────────────────────────────────────────────────────

if (types) {
  push(
    "CoachingRole has exactly the 3 canonical staff roles",
    /"admin_master"[\s\S]*"coach"[\s\S]*"assistant"/.test(types),
  );
  push(
    "COACHING_ROLES array exported",
    /export const COACHING_ROLES[\s\S]{0,200}"admin_master"[\s\S]{0,40}"coach"[\s\S]{0,40}"assistant"/.test(types),
  );
  push(
    "OnboardingStepId covers the 10 canonical steps",
    /OnboardingStepId[\s\S]{0,400}welcome[\s\S]{0,200}dashboard[\s\S]{0,200}athletes[\s\S]{0,200}training[\s\S]{0,200}financial[\s\S]{0,200}custody[\s\S]{0,200}clearing[\s\S]{0,200}distributions[\s\S]{0,200}help[\s\S]{0,200}settings/.test(types),
  );
  push(
    "STEP_VISIBILITY export present",
    /export const STEP_VISIBILITY\s*:\s*Record<OnboardingStepId, ReadonlySet<CoachingRole>>/.test(types),
  );
  push(
    "admin_master sees welcome",
    /welcome:\s*new Set\(\[[^\]]*"admin_master"/.test(types),
  );
  push(
    "custody is admin_master-only",
    /custody:\s*new Set\(\["admin_master"\]\)/.test(types),
  );
  push(
    "clearing is admin_master-only",
    /clearing:\s*new Set\(\["admin_master"\]\)/.test(types),
  );
  push(
    "distributions is admin_master-only",
    /distributions:\s*new Set\(\["admin_master"\]\)/.test(types),
  );
  push(
    "financial is admin_master-only",
    /financial:\s*new Set\(\["admin_master"\]\)/.test(types),
  );
  push(
    "coach sees dashboard + athletes + training",
    /dashboard:\s*new Set\(\[[^\]]*"coach"/.test(types)
      && /athletes:\s*new Set\(\[[^\]]*"coach"/.test(types)
      && /training:\s*new Set\(\[[^\]]*"coach"/.test(types),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// flows.ts
// ────────────────────────────────────────────────────────────────────────────

if (flows) {
  push(
    "buildFlowForRole exported",
    /export function buildFlowForRole\([\s\S]{0,120}role: CoachingRole/.test(flows),
  );
  push(
    "buildFlowForRole throws OnboardingFlowInputError for unknown role",
    /OnboardingFlowInputError[\s\S]{0,400}unknown coaching role/.test(flows),
  );
  push(
    "buildFlowForRole preserves CANONICAL_ORDER",
    /CANONICAL_ORDER\.filter\(/.test(flows),
  );
  push(
    "nextStepFor exported",
    /export function nextStepFor\(/.test(flows),
  );
  push(
    "stepIsVisibleFor exported",
    /export function stepIsVisibleFor\(/.test(flows),
  );
  push(
    "validateFlowInvariants exported",
    /export function validateFlowInvariants\(\)/.test(flows),
  );
  push(
    "validateFlowInvariants asserts admin_master sees every step",
    /admin_master must see step/.test(flows),
  );
  push(
    "validateFlowInvariants blocks coach from financial modules",
    /coach must NOT see financial-operator step/.test(flows),
  );
  push(
    "validateFlowInvariants enforces assistant ⊆ coach",
    /assistant must be subset of coach/.test(flows),
  );
  push(
    "OnboardingFlowInputError class exported",
    /export class OnboardingFlowInputError extends Error/.test(flows),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// index.ts
// ────────────────────────────────────────────────────────────────────────────

if (index) {
  push(
    "index re-exports buildFlowForRole",
    /buildFlowForRole/.test(index),
  );
  push(
    "index re-exports validateFlowInvariants",
    /validateFlowInvariants/.test(index),
  );
  push(
    "index re-exports CoachingRole type",
    /CoachingRole/.test(index),
  );
  push(
    "index re-exports OnboardingStepId type",
    /OnboardingStepId/.test(index),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// React wiring — use-onboarding hook
// ────────────────────────────────────────────────────────────────────────────

if (hook) {
  push(
    "hook imports buildFlowForRole",
    /import \{[\s\S]{0,200}buildFlowForRole/.test(hook),
  );
  push(
    "hook accepts UseOnboardingOptions with role",
    /UseOnboardingOptions\s*\{[\s\S]{0,600}role\?:\s*CoachingRole/.test(hook),
  );
  push(
    "hook per-role localStorage key (completion state segregated)",
    /storageKeyFor|STORAGE_KEY_PREFIX/.test(hook),
  );
  push(
    "hook totalSteps derived from flow length (not hard-coded)",
    /totalSteps = flow\.length/.test(hook)
      && !/const TOTAL_STEPS = 10/.test(hook),
  );
  push(
    "hook returns flow in its result",
    /flow,\s*isCompleted/.test(hook) || /flow,\n/.test(hook),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// overlay integration
// ────────────────────────────────────────────────────────────────────────────

if (overlay) {
  push(
    "overlay accepts optional role prop",
    /OnboardingOverlayProps\s*\{[\s\S]{0,600}role\?:\s*CoachingRole/.test(overlay),
  );
  push(
    "overlay passes role into useOnboarding",
    /useOnboarding\(\{\s*role/.test(overlay),
  );
  push(
    "overlay resolves step via flow[currentStep]",
    /flow\[currentStep\]/.test(overlay),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// tests
// ────────────────────────────────────────────────────────────────────────────

if (tests) {
  push(
    "tests cover admin_master full flow",
    /admin_master sees every step/.test(tests),
  );
  push(
    "tests enforce coach never sees custody/clearing/distributions/financial",
    /coach sees no custody \/ clearing \/ distributions \/ financial/.test(tests),
  );
  push(
    "tests enforce assistant subset of coach",
    /assistant flow is a subset of coach flow/.test(tests),
  );
  push(
    "tests cover nextStepFor terminal",
    /returns null when current is the last step/.test(tests),
  );
  push(
    "tests check validateFlowInvariants reports empty on canonical config",
    /reports no issues on the canonical configuration/.test(tests),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// finding self-reference
// ────────────────────────────────────────────────────────────────────────────

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L07-02-onboarding-nao-distingue-papeis-atleta-coach-admin-master.md",
);
const finding = safeRead(findingPath, "L07-02 finding present");
if (finding) {
  push(
    "finding references onboarding-flows module",
    /portal\/src\/lib\/onboarding-flows/.test(finding),
  );
  push(
    "finding references CI guard",
    /audit:onboarding-flows|check-onboarding-flows/.test(finding),
  );
  push(
    "finding documents role segregation (admin_master vs coach vs assistant)",
    /admin_master/.test(finding)
      && /coach/.test(finding)
      && /assistant/.test(finding),
  );
  push(
    "finding mentions custody/clearing are admin-only",
    /admin_master-only|admin-only|apenas admin/i.test(finding)
      && /custody|clearing/i.test(finding),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────────────

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} onboarding-flows checks passed.`,
);
if (failed > 0) {
  console.error("\nL07-02 invariants broken.");
  process.exit(1);
}
