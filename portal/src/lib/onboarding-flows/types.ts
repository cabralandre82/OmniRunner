/**
 * L07-02 — Role-aware onboarding flow (pure domain).
 *
 * The portal serves coaching-group staff only — athletes never
 * see the portal, they live in the mobile app. Inside the portal,
 * three staff roles coexist and have radically different needs:
 *
 *   - `admin_master`: owns the assessoria. Sees and operates every
 *     module — including financial (custody, clearing, OmniCoin
 *     distribution). Needs the full onboarding tour.
 *
 *   - `coach`: prescribes workouts and monitors athletes. Has no
 *     business with custody, clearing or distributions — those are
 *     finance-operator concerns they neither touch nor should see.
 *     Showing those modules in the tour only confuses them ("custody?
 *     clearing? what is this, a crypto wallet?") and inflates churn.
 *
 *   - `assistant`: a restricted coach (e.g. a new staffer, an
 *     intern). Sees the same modules as `coach` in the tour minus
 *     the financial overview and settings.
 *
 * This module is the pure, persona-less source of truth for "which
 * steps does role X see, and in which order?". It has no React,
 * no DOM, no i18n — it returns ordered arrays of canonical step
 * IDs that the UI layer translates.
 */

export type CoachingRole = "admin_master" | "coach" | "assistant";

export const COACHING_ROLES: ReadonlyArray<CoachingRole> = [
  "admin_master",
  "coach",
  "assistant",
];

/**
 * Canonical onboarding step identifiers. The portal UI owns copy,
 * icons and DOM selectors; this module only owns the *ordering*
 * and the *visibility rules*.
 *
 * Adding a new step:
 *   1. Add to this union (any new value must be unique).
 *   2. Add to STEP_VISIBILITY with explicit role coverage.
 *   3. Add to CANONICAL_ORDER preserving desired position.
 *   4. CI guard (check-onboarding-flows.ts) re-validates.
 */
export type OnboardingStepId =
  | "welcome"
  | "dashboard"
  | "athletes"
  | "training"
  | "financial"
  | "custody"
  | "clearing"
  | "distributions"
  | "help"
  | "settings";

export const ONBOARDING_STEPS: ReadonlyArray<OnboardingStepId> = [
  "welcome",
  "dashboard",
  "athletes",
  "training",
  "financial",
  "custody",
  "clearing",
  "distributions",
  "help",
  "settings",
];

/**
 * Canonical ordering used by every role's flow. Role-specific
 * flows are always a *subset* of this array, preserving the order —
 * we never reshuffle steps per role, only hide them.
 *
 * Rationale: product UX consistency. When a coach graduates to
 * admin_master (promotion) and re-takes the tour, the steps they
 * already saw appear in the same place.
 */
export const CANONICAL_ORDER: ReadonlyArray<OnboardingStepId> = ONBOARDING_STEPS;

/**
 * Per-step → set of roles that should see it. Steps absent from a
 * role's set are filtered out of that role's flow.
 *
 * Financial triad (`financial`, `custody`, `clearing`, `distributions`)
 * is admin_master-only because those modules are gated by RLS and
 * feature-flags to the admin_master role anyway — showing them in
 * the tour for a coach creates false expectations.
 */
export const STEP_VISIBILITY: Record<OnboardingStepId, ReadonlySet<CoachingRole>> = {
  welcome:       new Set(["admin_master", "coach", "assistant"]),
  dashboard:     new Set(["admin_master", "coach", "assistant"]),
  athletes:      new Set(["admin_master", "coach", "assistant"]),
  training:      new Set(["admin_master", "coach", "assistant"]),
  financial:     new Set(["admin_master"]),
  custody:       new Set(["admin_master"]),
  clearing:      new Set(["admin_master"]),
  distributions: new Set(["admin_master"]),
  help:          new Set(["admin_master", "coach", "assistant"]),
  settings:      new Set(["admin_master", "coach"]),
};
