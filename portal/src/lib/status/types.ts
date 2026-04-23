/**
 * L20-06 — Public status page value objects.
 *
 * The audit finding asks for a public page answering "Omni Runner está
 * operacional?" so that during an outage users don't flood support
 * tickets. This module is the domain layer consumed by:
 *
 *  - `GET /api/public/status` (aggregate endpoint the future
 *    `status.omnirunner.com` page pulls from);
 *  - integration tests that pin the worst-component-wins rule;
 *  - the static-site or external tool (Atlassian Statuspage, Better
 *    Stack, Cachet) that renders the page itself.
 *
 * Everything here is plain JSON-serialisable and framework-free.
 */

/**
 * Canonical user-visible components of the platform. Order matters —
 * it is the default display order on the status page and is enforced
 * by CI so that reshuffling the array is an intentional content PR.
 *
 * Adding a component is additive: extend the union, extend
 * {@link STATUS_COMPONENTS}, and update the runbook.
 */
export type StatusComponent =
  | "web"
  | "api"
  | "database"
  | "auth"
  | "payments"
  | "strava";

/**
 * Stable canonical ordering of {@link StatusComponent}. Consumers —
 * including the status page renderer — render in this exact order.
 */
export const STATUS_COMPONENTS: readonly StatusComponent[] = [
  "web",
  "api",
  "database",
  "auth",
  "payments",
  "strava",
] as const;

/**
 * Human-readable labels for {@link StatusComponent}. Only pt-BR for
 * now; i18n is a tracked follow-up (`L20-06-i18n`). Keeping the map
 * alongside the enum means adding a component without adding a label
 * is a compile error.
 */
export const STATUS_COMPONENT_LABELS: Record<StatusComponent, string> = {
  web: "App web",
  api: "API",
  database: "Banco de dados",
  auth: "Autenticação",
  payments: "Pagamentos",
  strava: "Integração Strava",
};

/**
 * Severity ladder for an individual component, ordered from best
 * (`operational`) to worst (`majorOutage`). The string literals are
 * the wire contract — they land verbatim in the JSON response and
 * map 1-to-1 to Atlassian Statuspage / Better Stack vocabulary, so
 * migrating to those platforms is a no-op for consumers.
 *
 * `unknown` is a first-class value and not a disguised failure: it
 * means a feed could not be fetched (external API down, timeout)
 * and the rest of the platform has no signal to infer the state
 * from. The status page MUST render `unknown` distinctly from
 * `operational` so users aren't reassured by stale data.
 */
export type StatusLevel =
  | "operational"
  | "degraded"
  | "partial_outage"
  | "major_outage"
  | "unknown";

/**
 * Canonical severity ordering — `rank(a)` vs `rank(b)`. Higher rank
 * = worse. Used by {@link aggregateLevel} so we don't depend on
 * array-index arithmetic sprinkled around consumers.
 */
const LEVEL_RANK: Record<StatusLevel, number> = {
  operational: 0,
  unknown: 1,
  degraded: 2,
  partial_outage: 3,
  major_outage: 4,
};

export function compareStatusLevels(
  a: StatusLevel,
  b: StatusLevel,
): number {
  return LEVEL_RANK[a] - LEVEL_RANK[b];
}

/**
 * The status of a single component.
 *
 * `observedAt` is an ISO-8601 UTC string so JSON-transport stays
 * human-readable and the renderer can display "observed 42s ago"
 * without needing extra metadata. `note` is an optional short
 * message the status page can surface (e.g. "investigando latência
 * em São Paulo"). Long-form incidents live elsewhere (Statuspage
 * incident timeline, future `incidents` table).
 */
export interface ComponentStatus {
  component: StatusComponent;
  level: StatusLevel;
  observedAt: string;
  note?: string;
}

/**
 * The aggregate status payload returned by `/api/public/status`.
 *
 * Invariants (enforced by {@link aggregateStatus}):
 *  - `components` contains exactly one entry per
 *    {@link StatusComponent}, in {@link STATUS_COMPONENTS} order.
 *  - `overall` is the worst level across `components`.
 *  - `generatedAt` is UTC ISO-8601.
 */
export interface AggregateStatus {
  overall: StatusLevel;
  components: readonly ComponentStatus[];
  generatedAt: string;
}

/**
 * Provider contract. A feed returns the current status for a single
 * component and is expected to **never throw** — network or parsing
 * errors must be collapsed into `level: 'unknown'` with a short
 * `note`. The aggregator relies on this so a single vendor outage
 * (e.g. Vercel status API timing out) cannot knock the whole status
 * endpoint offline.
 */
export interface StatusFeed {
  readonly component: StatusComponent;
  fetch(now: Date): Promise<ComponentStatus>;
}

/**
 * Lower bound on the cache TTL for the aggregator. Kept in the
 * value-object layer so the CI guard enforces it — fetching external
 * status feeds on every request risks hitting vendor rate limits
 * (Atlassian Statuspage caps at 1 rps on free tier) and leaks the
 * request volume of `status.omnirunner.com` visitors to third
 * parties.
 */
export const STATUS_CACHE_MIN_TTL_MS = 30_000;

/** Default cache TTL used by {@link createCachedAggregator}. */
export const STATUS_CACHE_DEFAULT_TTL_MS = 60_000;
