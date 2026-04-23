import { describe, expect, it } from "vitest";
import {
  ack,
  enqueue,
  markInFlight,
  pickReady,
  purgeCompleted,
  requeueDeadLetter,
  snapshot,
} from "./queue";
import { evaluateAlert } from "./policy";
import {
  DEFAULT_OFFLINE_ALERT_POLICY,
  DEFAULT_RETRY_POLICY,
  type SyncQueueState,
} from "./types";

const empty = (): SyncQueueState => ({ entries: [] });

describe("offline-sync queue", () => {
  it("enqueue is idempotent on id collision", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "attendance_checkin", payload: {}, now: 100 });
    s = enqueue(s, { id: "a", kind: "attendance_checkin", payload: { x: 2 }, now: 200 });
    expect(s.entries).toHaveLength(1);
    expect(s.entries[0]?.createdAt).toBe(100);
  });

  it("pickReady respects nextAttemptAt and limit", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "workout_completion", payload: {}, now: 100 });
    s = enqueue(s, { id: "b", kind: "workout_completion", payload: {}, now: 50 });
    const ready = pickReady(s, { now: 100, limit: 1 });
    expect(ready).toHaveLength(1);
    expect(ready[0]?.id).toBe("b");
  });

  it("ack(ok) transitions to done and stamps completedAt", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "session_note", payload: {}, now: 100 });
    s = markInFlight(s, "a", 120);
    s = ack(s, { id: "a", now: 150, result: { ok: true, retryable: false } });
    const entry = s.entries[0];
    expect(entry?.status).toBe("done");
    expect(entry?.completedAt).toBe(150);
    expect(entry?.attempts).toBe(1);
  });

  it("ack(fail, retryable) schedules next attempt with exponential backoff", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "session_note", payload: {}, now: 100 });
    const fixedRandom = () => 0.5;
    s = ack(s, {
      id: "a",
      now: 1000,
      result: { ok: false, retryable: true, errorCode: "NETWORK" },
      random: fixedRandom,
    });
    const entry = s.entries[0];
    expect(entry?.status).toBe("pending");
    expect(entry?.attempts).toBe(1);
    expect(entry?.nextAttemptAt).toBeGreaterThan(1000);
    expect(entry?.lastErrorCode).toBe("NETWORK");
  });

  it("ack(fail, non-retryable) dead-letters immediately", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "pairing_response", payload: {}, now: 100 });
    s = ack(s, {
      id: "a",
      now: 200,
      result: { ok: false, retryable: false, errorCode: "BAD_REQUEST" },
    });
    expect(s.entries[0]?.status).toBe("dead_letter");
    expect(s.entries[0]?.deadLetteredAt).toBe(200);
  });

  it("ack(fail, retryable) dead-letters after maxAttempts", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "custom", payload: {}, now: 0 });
    for (let i = 0; i < DEFAULT_RETRY_POLICY.maxAttempts; i += 1) {
      s = ack(s, {
        id: "a",
        now: 100 * (i + 1),
        result: { ok: false, retryable: true, errorCode: "NETWORK" },
        random: () => 0,
      });
    }
    expect(s.entries[0]?.status).toBe("dead_letter");
    expect(s.entries[0]?.attempts).toBe(DEFAULT_RETRY_POLICY.maxAttempts);
  });

  it("requeueDeadLetter returns entry to pending and resets attempts", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "custom", payload: {}, now: 0 });
    s = ack(s, { id: "a", now: 10, result: { ok: false, retryable: false } });
    expect(s.entries[0]?.status).toBe("dead_letter");
    s = requeueDeadLetter(s, "a", 50);
    const entry = s.entries[0];
    expect(entry?.status).toBe("pending");
    expect(entry?.attempts).toBe(0);
    expect(entry?.deadLetteredAt).toBeUndefined();
    expect(entry?.nextAttemptAt).toBe(50);
  });

  it("purgeCompleted drops old dones only", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "custom", payload: {}, now: 0 });
    s = enqueue(s, { id: "b", kind: "custom", payload: {}, now: 0 });
    s = ack(s, { id: "a", now: 100, result: { ok: true, retryable: false } });
    s = ack(s, { id: "b", now: 10_000, result: { ok: true, retryable: false } });
    s = purgeCompleted(s, 5_000, 12_000);
    expect(s.entries.map((e) => e.id).sort()).toEqual(["b"]);
  });

  it("snapshot reports counts and oldest pending age", () => {
    let s = empty();
    s = enqueue(s, { id: "a", kind: "custom", payload: {}, now: 100 });
    s = enqueue(s, { id: "b", kind: "custom", payload: {}, now: 500 });
    const snap = snapshot(s, 1000);
    expect(snap.pending).toBe(2);
    expect(snap.oldestPendingAgeMs).toBe(900);
  });
});

describe("evaluateAlert", () => {
  it("returns OK when under all thresholds", () => {
    const snap = {
      pending: 1,
      inFlight: 0,
      done: 0,
      failed: 0,
      deadLetter: 0,
      total: 1,
      oldestPendingAgeMs: 1000,
    };
    const alert = evaluateAlert(snap, DEFAULT_OFFLINE_ALERT_POLICY);
    expect(alert.code).toBe("OK");
    expect(alert.severity).toBe("info");
  });

  it("escalates to critical when a dead letter is present", () => {
    const snap = {
      pending: 0,
      inFlight: 0,
      done: 0,
      failed: 0,
      deadLetter: 1,
      total: 1,
      oldestPendingAgeMs: 0,
    };
    const alert = evaluateAlert(snap, DEFAULT_OFFLINE_ALERT_POLICY);
    expect(alert.code).toBe("DEAD_LETTERS_PRESENT");
    expect(alert.severity).toBe("critical");
  });

  it("warns on pending threshold", () => {
    const snap = {
      pending: DEFAULT_OFFLINE_ALERT_POLICY.pendingCountThreshold,
      inFlight: 0,
      done: 0,
      failed: 0,
      deadLetter: 0,
      total: 5,
      oldestPendingAgeMs: 100,
    };
    const alert = evaluateAlert(snap, DEFAULT_OFFLINE_ALERT_POLICY);
    expect(alert.code).toBe("PENDING_THRESHOLD");
    expect(alert.severity).toBe("warning");
  });

  it("warns on age threshold", () => {
    const snap = {
      pending: 1,
      inFlight: 0,
      done: 0,
      failed: 0,
      deadLetter: 0,
      total: 1,
      oldestPendingAgeMs: DEFAULT_OFFLINE_ALERT_POLICY.oldestPendingAgeMsThreshold,
    };
    const alert = evaluateAlert(snap, DEFAULT_OFFLINE_ALERT_POLICY);
    expect(alert.code).toBe("AGE_THRESHOLD");
    expect(alert.severity).toBe("warning");
  });

  it("escalates to critical when both pending + age trip", () => {
    const snap = {
      pending: DEFAULT_OFFLINE_ALERT_POLICY.pendingCountThreshold,
      inFlight: 0,
      done: 0,
      failed: 0,
      deadLetter: 0,
      total: 10,
      oldestPendingAgeMs: DEFAULT_OFFLINE_ALERT_POLICY.oldestPendingAgeMsThreshold,
    };
    const alert = evaluateAlert(snap, DEFAULT_OFFLINE_ALERT_POLICY);
    expect(alert.code).toBe("BOTH");
    expect(alert.severity).toBe("critical");
  });
});
