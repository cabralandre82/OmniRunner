/**
 * Route-policy cache (L13-03) — process-local LRU cache for the
 * portal middleware's `coaching_members` lookup.
 *
 * # Why this exists
 *
 * The portal middleware fires on every request. For each authenticated
 * non-platform request it issued a Postgres query against
 * `coaching_members` to confirm the cookie-stored `(group_id, role)`
 * pair was still valid. A single dashboard page-load triggers ~15 RSC
 * + ~8 fetch calls — so 23 round-trips to Supabase on every navigation,
 * each ~50 ms. Under load this exhausts the connection pool.
 *
 * # Design
 *
 *   - **Process-local LRU** (Map insertion order). No external Redis
 *     dependency — Vercel functions are short-lived (< 5 min warm), so
 *     a single in-memory map per instance is enough to absorb the
 *     `15 RSC + 8 fetch` burst without a single DB hit. Cold starts
 *     pay one round-trip, which we budget for.
 *
 *   - **Short TTL (60 s)** — chosen to bound the staleness window for
 *     role demotions. If an admin removes a coach, the coach can still
 *     hit admin pages for at most 60 s before the cache expires. This
 *     trade-off is documented in `docs/audit/findings/L13-03-*.md` and
 *     is why we DO NOT cache for hours.
 *
 *   - **Negative caching** (`NULL` membership) — if the user has no
 *     active membership in the queried group, we cache that absence
 *     too. Same TTL. Otherwise an unauthorised user could trigger
 *     infinite Postgres queries by spamming `/dashboard` on a
 *     just-removed account.
 *
 *   - **Bounded size** (`MAX_ENTRIES = 5_000`) — protects against memory
 *     blowup if a single instance sees many distinct users in one warm
 *     window (e.g. a misbehaving cron iterating all athletes).
 *
 *   - **Explicit invalidation API** (`invalidateMembership`,
 *     `invalidateAllForUser`) — must be called by every mutation that
 *     can change `(user_id, group_id, role)`: invite acceptance,
 *     role change, member removal, role demotion. The portal admin UI
 *     is the only writer.
 *
 * # Threat model
 *
 *   - **Stale-cache privilege grant**: bounded by `TTL_MS`. Acceptable.
 *   - **Negative-cache DoS by spammer**: not solved here — the cache
 *     ABSORBS the spam (one DB hit per minute per spammer). Rate
 *     limiting is `lib/rate-limit.ts`'s job.
 *   - **Cross-tenant leak**: cache key is `${userId}:${groupId}` and
 *     the value never contains data from a different group. A user
 *     fetching membership for group A cannot poison the entry for
 *     group B.
 *   - **PII**: cache value contains only `role` (plus null sentinel).
 *     No display names, no emails. Logs (this module never logs)
 *     would not leak anything sensitive even if accidentally enabled.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

/** Sentinel for "we know this user has no membership in that group". */
export const MEMBERSHIP_NONE: unique symbol = Symbol("membership-none");

export type CachedMembership =
  | { readonly role: string }
  | typeof MEMBERSHIP_NONE;

interface CacheEntry {
  value: CachedMembership;
  expiresAt: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tunables (exposed for tests via setMembershipCacheTTLForTests)
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_TTL_MS = 60_000;
const MAX_ENTRIES = 5_000;

let ttlMs = DEFAULT_TTL_MS;

/**
 * Test-only hook to shrink the TTL so tests can exercise expiry
 * without sleeping. Resetting to `null` restores the default.
 *
 * @internal
 */
export function setMembershipCacheTTLForTests(value: number | null): void {
  ttlMs = value ?? DEFAULT_TTL_MS;
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage
// ─────────────────────────────────────────────────────────────────────────────

const cache = new Map<string, CacheEntry>();

function buildKey(userId: string, groupId: string): string {
  return `${userId}:${groupId}`;
}

function nowMs(): number {
  return Date.now();
}

function pruneOldestIfNeeded(): void {
  if (cache.size <= MAX_ENTRIES) return;
  const overflow = cache.size - MAX_ENTRIES;
  let removed = 0;
  // Map preserves insertion order; forEach iterates oldest-first.
  // We collect keys first to avoid mutating during iteration.
  const toDelete: string[] = [];
  cache.forEach((_value, key) => {
    if (removed < overflow) {
      toDelete.push(key);
      removed++;
    }
  });
  for (const k of toDelete) cache.delete(k);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Look up a cached membership. Returns `undefined` on miss / expiry.
 * Expired entries are removed eagerly to avoid the cache becoming a
 * graveyard of stale rows.
 */
export function getCachedMembership(
  userId: string,
  groupId: string,
): CachedMembership | undefined {
  const key = buildKey(userId, groupId);
  const entry = cache.get(key);
  if (!entry) return undefined;
  if (entry.expiresAt <= nowMs()) {
    cache.delete(key);
    return undefined;
  }
  // Refresh insertion order so this entry becomes "recently used"
  // (LRU semantics).
  cache.delete(key);
  cache.set(key, entry);
  return entry.value;
}

/**
 * Store a membership. Pass `MEMBERSHIP_NONE` for negative caching
 * ("user has no membership in this group"). Both forms use the same
 * TTL.
 */
export function setCachedMembership(
  userId: string,
  groupId: string,
  value: CachedMembership,
): void {
  const key = buildKey(userId, groupId);
  cache.set(key, { value, expiresAt: nowMs() + ttlMs });
  pruneOldestIfNeeded();
}

/**
 * Drop a single `(user, group)` cache entry. Call this from any
 * mutation that changes the user's role within the group, OR removes
 * them from the group. Idempotent (no-op when no entry).
 */
export function invalidateMembership(userId: string, groupId: string): void {
  cache.delete(buildKey(userId, groupId));
}

/**
 * Drop every cached entry for a given user across all groups. Call
 * this when a user is fully removed from staff, demoted globally, or
 * when the platform admin page edits something multi-group.
 */
export function invalidateAllForUser(userId: string): void {
  const prefix = `${userId}:`;
  const toDelete: string[] = [];
  cache.forEach((_value, key) => {
    if (key.startsWith(prefix)) toDelete.push(key);
  });
  for (const k of toDelete) cache.delete(k);
}

/**
 * Wipe the entire cache. Used by tests for isolation; callable from
 * production only as a last-resort "stampede" recovery.
 */
export function clearMembershipCache(): void {
  cache.clear();
}

/** @internal — for tests / observability dashboards. */
export function membershipCacheSize(): number {
  return cache.size;
}
