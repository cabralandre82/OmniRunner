/**
 * L05-12 — Deterministic challenge tie-break ordering.
 *
 * Distance challenges that ranked athletes by `total_distance DESC`
 * with `LIMIT 1` left ties to the storage engine's row-return order
 * (effectively undefined). The prize would be awarded to whichever
 * row Postgres surfaced first — repeatable in steady state but not
 * across replicas, vacuum cycles, or partition pruning.
 *
 * The official tie-break (documented in every challenge "Rules"
 * section) is now:
 *
 *   1. Higher metric value (distance, duration, elevation, etc.)
 *   2. Lower elapsed time (faster wins between equal volumes)
 *   3. Earlier completion timestamp (first-to-reach wins)
 *   4. Lower athlete UUID (stable, replication-safe deterministic
 *      tie-break of last resort — never ties)
 *
 * This module is pure: callers feed it leaderboard rows and receive
 * the canonical ordering. The SQL counterpart appears in any RPC
 * that picks winners; both must implement the same ordering or the
 * `tie-break-parity` CI guard fails.
 */

export interface ChallengeLeaderboardRow {
  athleteUserId: string;
  metricValue: number;
  totalDurationSeconds: number;
  completedAt: string;
}

/**
 * Compare two leaderboard rows. Returns a negative number if `a`
 * ranks ahead of `b`, positive if `b` ranks ahead, 0 only when
 * the entire 4-tuple matches (impossible in practice because
 * `athleteUserId` is unique).
 */
export function compareLeaderboardRows(
  a: ChallengeLeaderboardRow,
  b: ChallengeLeaderboardRow,
): number {
  if (a.metricValue !== b.metricValue) return b.metricValue - a.metricValue;
  if (a.totalDurationSeconds !== b.totalDurationSeconds) {
    return a.totalDurationSeconds - b.totalDurationSeconds;
  }
  const aTs = Date.parse(a.completedAt);
  const bTs = Date.parse(b.completedAt);
  if (Number.isFinite(aTs) && Number.isFinite(bTs) && aTs !== bTs) {
    return aTs - bTs;
  }
  return a.athleteUserId.localeCompare(b.athleteUserId);
}

export function rankLeaderboard(
  rows: ReadonlyArray<ChallengeLeaderboardRow>,
): ChallengeLeaderboardRow[] {
  return [...rows].sort(compareLeaderboardRows);
}

export function pickWinner(
  rows: ReadonlyArray<ChallengeLeaderboardRow>,
): ChallengeLeaderboardRow | null {
  if (rows.length === 0) return null;
  return rankLeaderboard(rows)[0];
}

/**
 * Equivalent SQL ORDER BY for an RPC implementing the same tie-break:
 *
 *   ORDER BY metric_value DESC,
 *            total_duration_seconds ASC,
 *            completed_at ASC,
 *            athlete_user_id ASC
 *
 * Exposed as a string so the parity guard can grep migrations.
 */
export const CHALLENGE_TIE_BREAK_SQL_ORDER =
  "metric_value DESC, total_duration_seconds ASC, completed_at ASC, athlete_user_id ASC";
