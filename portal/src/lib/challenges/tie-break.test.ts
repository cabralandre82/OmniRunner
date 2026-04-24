import { describe, it, expect } from "vitest";
import {
  compareLeaderboardRows,
  pickWinner,
  rankLeaderboard,
  type ChallengeLeaderboardRow,
} from "./tie-break";

const row = (
  partial: Partial<ChallengeLeaderboardRow> & { athleteUserId: string },
): ChallengeLeaderboardRow => ({
  metricValue: 100,
  totalDurationSeconds: 3600,
  completedAt: "2026-04-21T12:00:00Z",
  ...partial,
});

describe("L05-12 challenge tie-break", () => {
  it("higher metric value wins", () => {
    const a = row({ athleteUserId: "a", metricValue: 110 });
    const b = row({ athleteUserId: "b", metricValue: 90 });
    expect(compareLeaderboardRows(a, b)).toBeLessThan(0);
    expect(pickWinner([a, b])?.athleteUserId).toBe("a");
  });

  it("equal metric: lower total duration wins (faster pace)", () => {
    const a = row({ athleteUserId: "a", totalDurationSeconds: 3700 });
    const b = row({ athleteUserId: "b", totalDurationSeconds: 3500 });
    expect(pickWinner([a, b])?.athleteUserId).toBe("b");
  });

  it("equal metric+duration: earlier completion wins", () => {
    const a = row({
      athleteUserId: "a",
      completedAt: "2026-04-21T12:01:00Z",
    });
    const b = row({
      athleteUserId: "b",
      completedAt: "2026-04-21T11:59:00Z",
    });
    expect(pickWinner([a, b])?.athleteUserId).toBe("b");
  });

  it("ties of last resort fall back to athlete uuid lexicographic order", () => {
    const a = row({ athleteUserId: "ffff" });
    const b = row({ athleteUserId: "00aa" });
    expect(pickWinner([a, b])?.athleteUserId).toBe("00aa");
  });

  it("rankLeaderboard is stable across replays (no Math.random)", () => {
    const rows: ChallengeLeaderboardRow[] = [
      row({ athleteUserId: "1", metricValue: 50 }),
      row({ athleteUserId: "2", metricValue: 50 }),
      row({ athleteUserId: "3", metricValue: 50 }),
    ];
    const a = rankLeaderboard(rows).map((r) => r.athleteUserId);
    const b = rankLeaderboard(rows).map((r) => r.athleteUserId);
    expect(a).toEqual(b);
    expect(a).toEqual(["1", "2", "3"]);
  });

  it("pickWinner returns null on empty leaderboard", () => {
    expect(pickWinner([])).toBeNull();
  });
});
