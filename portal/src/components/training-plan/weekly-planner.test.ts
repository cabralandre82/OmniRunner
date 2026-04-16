import { describe, it, expect } from "vitest";
import type { WorkoutRelease, ReleaseBlock } from "./types";

// ── Helpers mirroring the logic inside WeekBlock ──────────────────────────────

type Status = WorkoutRelease["release_status"];

function makeWorkout(status: Status): WorkoutRelease {
  return {
    id: "workout-id",
    scheduled_date: "2026-04-14",
    workout_order: 1,
    release_status: status,
    workout_type: "continuous",
    workout_label: null,
    coach_notes: null,
    video_url: null,
    content_version: 1,
    content_snapshot: null,
    template: null,
    completed: [],
    feedback: [],
  };
}

/** Mirrors the activeWorkouts filter in WeekBlock */
function activeWorkouts(workouts: WorkoutRelease[]) {
  return workouts.filter(
    (w) => !["cancelled", "replaced", "archived"].includes(w.release_status),
  );
}

// ── Mirrors the initialBlocks helper in WorkoutActionDrawer ──────────────────

function makeBlock(order: number): ReleaseBlock {
  return {
    order_index: order,
    block_type: "interval",
    duration_seconds: null,
    distance_meters: 1000,
    target_pace_min_sec_per_km: 255,
    target_pace_max_sec_per_km: 275,
    target_hr_zone: 4,
    target_hr_min: null,
    target_hr_max: null,
    rpe_target: null,
    repeat_count: null,
    notes: null,
  };
}

function initialBlocks(workout: WorkoutRelease | null): ReleaseBlock[] {
  if (!workout) return [];
  const snap = workout.content_snapshot?.blocks;
  if (snap && snap.length > 0) return snap;
  const tpl = workout.template?.coaching_workout_blocks;
  if (tpl && tpl.length > 0) return [...tpl].sort((a, b) => a.order_index - b.order_index);
  return [];
}

// ─────────────────────────────────────────────────────────────────────────────

describe("WeekBlock — active workout counting", () => {
  it("excludes cancelled workouts from total", () => {
    const workouts = [
      makeWorkout("draft"),
      makeWorkout("released"),
      makeWorkout("cancelled"),
    ];
    expect(activeWorkouts(workouts)).toHaveLength(2);
  });

  it("excludes replaced workouts from total", () => {
    const workouts = [makeWorkout("completed"), makeWorkout("replaced")];
    expect(activeWorkouts(workouts)).toHaveLength(1);
  });

  it("excludes archived workouts from total", () => {
    const workouts = [makeWorkout("completed"), makeWorkout("archived")];
    expect(activeWorkouts(workouts)).toHaveLength(1);
  });

  it("counts 3 active after 1 cancellation (regression: was showing 4)", () => {
    const workouts = [
      makeWorkout("released"),
      makeWorkout("released"),
      makeWorkout("released"),
      makeWorkout("cancelled"),
    ];
    const active = activeWorkouts(workouts);
    expect(active).toHaveLength(3);
    const completed = active.filter((w) => w.release_status === "completed");
    expect(completed).toHaveLength(0);
  });

  it("keeps draft, scheduled, released, in_progress, completed", () => {
    const statuses: Status[] = ["draft", "scheduled", "released", "in_progress", "completed"];
    const workouts = statuses.map(makeWorkout);
    expect(activeWorkouts(workouts)).toHaveLength(statuses.length);
  });
});

describe("WorkoutActionDrawer — initialBlocks", () => {
  it("returns empty array when workout is null", () => {
    expect(initialBlocks(null)).toEqual([]);
  });

  it("returns empty array when both snapshot and template are absent", () => {
    expect(initialBlocks(makeWorkout("draft"))).toEqual([]);
  });

  it("prefers content_snapshot.blocks over template blocks", () => {
    const snapBlock = makeBlock(0);
    const tplBlock = makeBlock(0);
    const workout: WorkoutRelease = {
      ...makeWorkout("draft"),
      content_snapshot: { blocks: [snapBlock] },
      template: {
        id: "t1",
        name: "T",
        description: null,
        coaching_workout_blocks: [tplBlock, makeBlock(1)],
      },
    };
    expect(initialBlocks(workout)).toEqual([snapBlock]);
  });

  it("falls back to template blocks when content_snapshot.blocks is empty", () => {
    const b0 = makeBlock(0);
    const b1 = makeBlock(1);
    const workout: WorkoutRelease = {
      ...makeWorkout("draft"),
      content_snapshot: { blocks: [] },
      template: {
        id: "t1",
        name: "T",
        description: null,
        coaching_workout_blocks: [b1, b0], // intentionally out of order
      },
    };
    const result = initialBlocks(workout);
    expect(result).toHaveLength(2);
    expect(result[0].order_index).toBe(0);
    expect(result[1].order_index).toBe(1);
  });

  it("falls back to template blocks when content_snapshot is null", () => {
    const b = makeBlock(0);
    const workout: WorkoutRelease = {
      ...makeWorkout("draft"),
      content_snapshot: null,
      template: {
        id: "t1",
        name: "T",
        description: null,
        coaching_workout_blocks: [b],
      },
    };
    expect(initialBlocks(workout)).toEqual([b]);
  });

  it("returns empty array when template has no blocks and snapshot is null", () => {
    const workout: WorkoutRelease = {
      ...makeWorkout("draft"),
      template: { id: "t1", name: "T", description: null, coaching_workout_blocks: [] },
    };
    expect(initialBlocks(workout)).toEqual([]);
  });
});
