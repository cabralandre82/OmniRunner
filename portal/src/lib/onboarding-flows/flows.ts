/**
 * L07-02 — Flow builder (pure domain).
 */

import {
  CANONICAL_ORDER,
  COACHING_ROLES,
  type CoachingRole,
  type OnboardingStepId,
  STEP_VISIBILITY,
} from "./types";

export class OnboardingFlowInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OnboardingFlowInputError";
  }
}

/**
 * Resolve the ordered list of step IDs for a given role.
 * Preserves CANONICAL_ORDER; simply hides steps whose visibility
 * set does not include the role.
 *
 * Throws OnboardingFlowInputError for unknown roles so the caller
 * never silently ships an empty tour.
 */
export function buildFlowForRole(
  role: CoachingRole,
): ReadonlyArray<OnboardingStepId> {
  if (!COACHING_ROLES.includes(role)) {
    throw new OnboardingFlowInputError(
      `unknown coaching role: "${role as string}"`,
    );
  }
  return CANONICAL_ORDER.filter((stepId) =>
    STEP_VISIBILITY[stepId].has(role),
  );
}

/**
 * Returns the full set of role-specific flow lengths. Useful for
 * UI progress counters that need to compute "step N of M" before
 * the flow is rendered.
 */
export function flowLengthForRole(role: CoachingRole): number {
  return buildFlowForRole(role).length;
}

/**
 * True when `stepId` is part of the flow for `role`.
 * Equivalent to `STEP_VISIBILITY[stepId].has(role)`, but exported
 * so consumers don't depend on the internal Set shape.
 */
export function stepIsVisibleFor(
  stepId: OnboardingStepId,
  role: CoachingRole,
): boolean {
  return STEP_VISIBILITY[stepId]?.has(role) ?? false;
}

/**
 * Advance one step within a role's flow. Returns the next step's
 * ID or `null` when the current step is the last one.
 *
 * Pure arithmetic on CANONICAL_ORDER — the UI can still walk
 * indices if it prefers, but this helper keeps the role awareness
 * next to the ordering.
 */
export function nextStepFor(
  current: OnboardingStepId | null,
  role: CoachingRole,
): OnboardingStepId | null {
  const flow = buildFlowForRole(role);
  if (current === null) return flow[0] ?? null;
  const idx = flow.indexOf(current);
  if (idx === -1) {
    throw new OnboardingFlowInputError(
      `step "${current}" is not part of the flow for role "${role}"`,
    );
  }
  return flow[idx + 1] ?? null;
}

/**
 * Role-specific sanity check used by the CI guard. Returns a
 * non-empty list of issues if any invariant is violated.
 */
export function validateFlowInvariants(): string[] {
  const issues: string[] = [];
  const canonicalSet = new Set<OnboardingStepId>(CANONICAL_ORDER);

  for (const stepId of CANONICAL_ORDER) {
    if (!STEP_VISIBILITY[stepId]) {
      issues.push(`step ${stepId} missing visibility entry`);
    }
  }
  for (const stepId of Object.keys(STEP_VISIBILITY) as OnboardingStepId[]) {
    if (!canonicalSet.has(stepId)) {
      issues.push(`visibility entry for unknown step ${stepId}`);
    }
  }

  // admin_master must see every step — they own the assessoria and
  // no module is hidden from them at the UI layer.
  for (const stepId of CANONICAL_ORDER) {
    if (!STEP_VISIBILITY[stepId]?.has("admin_master")) {
      issues.push(`admin_master must see step ${stepId}`);
    }
  }

  // Coach must never see financial operator modules.
  for (const forbidden of [
    "custody",
    "clearing",
    "distributions",
    "financial",
  ] as OnboardingStepId[]) {
    if (STEP_VISIBILITY[forbidden]?.has("coach")) {
      issues.push(
        `coach must NOT see financial-operator step ${forbidden}`,
      );
    }
  }

  // Assistant must be a subset of coach (i.e. never see anything
  // a coach can't see).
  for (const stepId of CANONICAL_ORDER) {
    if (
      STEP_VISIBILITY[stepId]?.has("assistant")
      && !STEP_VISIBILITY[stepId]?.has("coach")
    ) {
      issues.push(
        `assistant sees ${stepId} but coach does not — assistant must be subset of coach`,
      );
    }
  }

  // Every role must see `welcome`.
  for (const role of COACHING_ROLES) {
    if (!STEP_VISIBILITY.welcome.has(role)) {
      issues.push(`role ${role} must see 'welcome'`);
    }
  }

  return issues;
}
