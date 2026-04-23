/**
 * L17-02 — portal/src/lib bounded-context manifest.
 *
 * Single source of truth for how the 45+ files and directories in
 * `portal/src/lib` are classified into bounded contexts.  The
 * {@link CONTEXT_MANIFEST} table drives the CI guard
 * (`audit:portal-bounded-contexts`) which enforces:
 *
 *   1. Every non-test `.ts` file and every subdirectory in
 *      `portal/src/lib` is claimed by exactly one context.
 *   2. New files MUST be added to this manifest — dedicated
 *      test in the CI guard fails on unclaimed entries.
 *   3. Cross-context imports obey the {@link LAYERING_RULES}
 *      direction graph: pure-domain never touches infra, etc.
 *
 * No runtime imports should come from this file; it is metadata.
 */

// ────────────────────────────────────────────────────────────────────
// Contexts
// ────────────────────────────────────────────────────────────────────

export const BOUNDED_CONTEXTS = [
  "financial",
  "security",
  "platform",
  "infra",
  "domain",
  "integration",
  "shared",
  "qa",
  "boundaries",
] as const;
export type BoundedContext = (typeof BOUNDED_CONTEXTS)[number];

// ────────────────────────────────────────────────────────────────────
// Manifest
// ────────────────────────────────────────────────────────────────────

/**
 * Every non-test top-level entry (`*.ts` file OR subdirectory)
 * inside `portal/src/lib` MUST appear here.  Keep the list sorted
 * alphabetically by `path` to minimise merge conflicts.
 */
export interface ContextEntry {
  /** Basename relative to portal/src/lib (e.g. "custody.ts" or "billing"). */
  readonly path: string;
  /** Logical bounded context owning this entry. */
  readonly context: BoundedContext;
  /** Short PT-BR rationale — displayed in CI output on failures. */
  readonly note?: string;
}

export const CONTEXT_MANIFEST: readonly ContextEntry[] = [
  { path: "__qa__",                    context: "qa" },
  { path: "_boundaries",               context: "boundaries" },
  { path: "actions.ts",                context: "shared",      note: "server actions helper — cross-context bootstrap" },
  { path: "analytics.ts",              context: "platform",    note: "product telemetry" },
  { path: "api",                       context: "infra",       note: "HTTP helpers / canonical envelopes" },
  { path: "api-handler.ts",            context: "infra",       note: "Next.js route wrapper" },
  { path: "attribution.ts",            context: "platform",    note: "attribution/UTM" },
  { path: "audit.ts",                  context: "security",    note: "audit log writers" },
  { path: "billing",                   context: "financial",   note: "subscription billing" },
  { path: "cache.ts",                  context: "infra" },
  { path: "clearing.ts",               context: "financial" },
  { path: "cron-health.ts",            context: "platform" },
  { path: "cron-sla.ts",               context: "platform" },
  { path: "custody.ts",                context: "financial" },
  { path: "deep-links.ts",             context: "integration" },
  { path: "export.ts",                 context: "shared" },
  { path: "feature-flags.ts",          context: "platform" },
  { path: "first-run-onboarding",      context: "domain",      note: "L22-01 pure-domain state machine" },
  { path: "format.ts",                 context: "shared" },
  { path: "fx",                        context: "financial",   note: "FX rates — currency conversion" },
  { path: "iof",                       context: "financial",   note: "L09-05 pure-domain IOF primitive" },
  { path: "logger.ts",                 context: "infra" },
  { path: "metrics.ts",                context: "platform" },
  { path: "middleware-routes.test.ts", context: "qa",          note: "Next.js middleware contract test" },
  { path: "money.ts",                  context: "financial" },
  { path: "observability",             context: "platform" },
  { path: "offline-sync",              context: "domain",      note: "L07-03 pure-domain sync queue" },
  { path: "og-metadata.ts",            context: "integration", note: "OpenGraph payload" },
  { path: "omnicoin-narrative",        context: "domain",      note: "L22-02 pure-domain copy" },
  { path: "onboarding-flows",          context: "domain",      note: "L07-02 role-aware flow" },
  { path: "openapi",                   context: "infra" },
  { path: "partnerships.test.ts",      context: "qa" },
  { path: "periodization",             context: "domain",      note: "L23-06 periodization wizard" },
  { path: "platform-fee-types.ts",     context: "financial" },
  { path: "product-event-schema.ts",   context: "integration", note: "outbox schema" },
  { path: "qa-e2e-antifraud.test.ts",  context: "qa" },
  { path: "qa-e2e-concurrency.test.ts", context: "qa" },
  { path: "qa-e2e-idempotency.test.ts", context: "qa" },
  { path: "qa-e2e-smoke.test.ts",      context: "qa" },
  { path: "qa-reconciliation.test.ts", context: "qa" },
  { path: "rate-limit.ts",             context: "security" },
  { path: "redis.ts",                  context: "infra" },
  { path: "roles.ts",                  context: "security",    note: "authZ role gate" },
  { path: "route-policy-cache.ts",     context: "infra" },
  { path: "route-policy.ts",           context: "infra" },
  { path: "schemas.ts",                context: "infra",       note: "zod schemas for HTTP payloads" },
  { path: "security",                  context: "security" },
  { path: "sensitive-access.ts",       context: "security" },
  { path: "status",                    context: "platform" },
  { path: "supabase",                  context: "infra" },
  { path: "swap.ts",                   context: "financial" },
  { path: "training-load",             context: "domain",      note: "L21-04 TSS / CTL / ATL primitive" },
  { path: "wallet-invariants.ts",      context: "financial" },
  { path: "webhook-ip-allowlist.ts",   context: "security" },
  { path: "webhook.ts",                context: "security",    note: "HMAC-verified inbound webhook" },
];

// ────────────────────────────────────────────────────────────────────
// Layering rules
// ────────────────────────────────────────────────────────────────────

/**
 * Allowed directed edges.  An entry `[A, B]` means files classified
 * in context A may import files classified in context B.  Self-edges
 * are implicit (a context can always import itself).
 *
 * **Interpretation:**
 *  - `domain` is the lowest layer (pure functional value objects);
 *    it may only depend on `shared` and `boundaries` (metadata).
 *    It MUST NOT depend on `financial`, `infra`, `security`,
 *    `platform`, `integration`.
 *  - `financial`, `security`, `platform` are the "service" layer:
 *    they may depend on `infra`, `shared`, `domain`, `boundaries`,
 *    but MUST NOT depend on each other (avoid tangled cross-context
 *    cycles — go through the HTTP envelope instead).
 *  - `integration` sits between service and domain; may use `domain`
 *    and `shared`, but MUST NOT touch infra directly.
 *  - `infra` is the bottom plumbing; depends only on `shared` and
 *    `boundaries`.
 *  - `qa` is above everything and can import from any layer.
 *
 * This is deliberately conservative; the CI guard treats missing
 * edges as violations.  Relaxations must land with a reviewed ADR.
 */
export const LAYERING_RULES: ReadonlyArray<[BoundedContext, BoundedContext]> = [
  // qa sees all
  ["qa", "financial"],
  ["qa", "security"],
  ["qa", "platform"],
  ["qa", "infra"],
  ["qa", "domain"],
  ["qa", "integration"],
  ["qa", "shared"],
  ["qa", "boundaries"],

  // integration → domain/shared/infra (read-only payload adapters)
  ["integration", "domain"],
  ["integration", "shared"],
  ["integration", "infra"],

  // service layer
  ["financial", "infra"],
  ["financial", "domain"],
  ["financial", "shared"],
  ["financial", "security"],
  ["financial", "platform"],

  ["security", "infra"],
  ["security", "shared"],
  ["security", "domain"],

  ["platform", "infra"],
  ["platform", "shared"],
  ["platform", "domain"],

  // infra has only shared + boundaries
  ["infra", "shared"],

  // domain has nothing outbound except shared (pure value objects)
  ["domain", "shared"],

  // shared is a leaf
  // boundaries has no outbound edges — it is pure metadata.
];

// ────────────────────────────────────────────────────────────────────
// Query helpers (pure)
// ────────────────────────────────────────────────────────────────────

export function contextOf(path: string): BoundedContext | null {
  const e = CONTEXT_MANIFEST.find((m) => m.path === path);
  return e ? e.context : null;
}

export function allowsImport(
  source: BoundedContext,
  target: BoundedContext,
): boolean {
  if (source === target) return true;
  return LAYERING_RULES.some(
    ([s, t]) => s === source && t === target,
  );
}

export function contextsWithMembers(): ReadonlyArray<{
  context: BoundedContext;
  paths: readonly string[];
}> {
  return BOUNDED_CONTEXTS.map((c) => ({
    context: c,
    paths: CONTEXT_MANIFEST.filter((m) => m.context === c).map((m) => m.path),
  }));
}
