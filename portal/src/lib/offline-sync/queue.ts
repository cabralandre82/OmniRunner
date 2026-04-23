/**
 * L07-03 — Pure offline-sync queue reducer.
 *
 * All functions are deterministic and free of side effects:
 * they take a {@link SyncQueueState} plus inputs and return a
 * new state. Callers inject `now` + `random` to keep tests
 * reproducible; the real app wires them to `Date.now()` and
 * `Math.random()`.
 *
 * See {@link ./types.ts} for the data model and
 * {@link ./policy.ts} for the retry + alert helpers.
 */

import {
  DEFAULT_RETRY_POLICY,
  type RetryPolicy,
  type SyncEntry,
  type SyncEntryKind,
  type SyncQueueState,
  type SyncResult,
} from "./types";
import {
  computeNextAttemptAt,
} from "./policy";

export interface EnqueueInput {
  id: string;
  kind: SyncEntryKind;
  payload: Record<string, unknown>;
  now: number;
}

export function enqueue(
  state: SyncQueueState,
  input: EnqueueInput,
): SyncQueueState {
  if (state.entries.some((e) => e.id === input.id)) {
    return state;
  }
  const entry: SyncEntry = {
    id: input.id,
    kind: input.kind,
    payload: input.payload,
    createdAt: input.now,
    updatedAt: input.now,
    attempts: 0,
    status: "pending",
    nextAttemptAt: input.now,
  };
  return { entries: [...state.entries, entry] };
}

export interface PickInput {
  now: number;
  limit?: number;
}

export function pickReady(
  state: SyncQueueState,
  input: PickInput,
): SyncEntry[] {
  const limit = input.limit ?? 1;
  const ready = state.entries
    .filter((e) => e.status === "pending" && e.nextAttemptAt <= input.now)
    .sort((a, b) => a.nextAttemptAt - b.nextAttemptAt || a.createdAt - b.createdAt);
  return ready.slice(0, Math.max(0, limit));
}

export function markInFlight(
  state: SyncQueueState,
  id: string,
  now: number,
): SyncQueueState {
  return mapEntry(state, id, (e) => {
    if (e.status !== "pending") return e;
    return { ...e, status: "in_flight", updatedAt: now };
  });
}

export interface AckInput {
  id: string;
  now: number;
  result: SyncResult;
  retryPolicy?: RetryPolicy;
  random?: () => number;
}

export function ack(
  state: SyncQueueState,
  input: AckInput,
): SyncQueueState {
  const policy = input.retryPolicy ?? DEFAULT_RETRY_POLICY;
  return mapEntry(state, input.id, (e) => {
    if (e.status === "done" || e.status === "dead_letter") return e;

    if (input.result.ok) {
      return {
        ...e,
        status: "done",
        updatedAt: input.now,
        completedAt: input.now,
        attempts: e.attempts + 1,
        lastErrorCode: undefined,
        lastErrorMessage: undefined,
      };
    }

    const attempts = e.attempts + 1;

    if (!input.result.retryable) {
      return {
        ...e,
        status: "dead_letter",
        updatedAt: input.now,
        deadLetteredAt: input.now,
        attempts,
        lastErrorCode: input.result.errorCode,
        lastErrorMessage: input.result.errorMessage,
      };
    }

    if (attempts >= policy.maxAttempts) {
      return {
        ...e,
        status: "dead_letter",
        updatedAt: input.now,
        deadLetteredAt: input.now,
        attempts,
        lastErrorCode: input.result.errorCode,
        lastErrorMessage: input.result.errorMessage,
      };
    }

    const nextAttemptAt = computeNextAttemptAt({
      attempts,
      now: input.now,
      policy,
      random: input.random,
    });

    return {
      ...e,
      status: "pending",
      updatedAt: input.now,
      attempts,
      nextAttemptAt,
      lastErrorCode: input.result.errorCode,
      lastErrorMessage: input.result.errorMessage,
    };
  });
}

export function requeueDeadLetter(
  state: SyncQueueState,
  id: string,
  now: number,
): SyncQueueState {
  return mapEntry(state, id, (e) => {
    if (e.status !== "dead_letter") return e;
    return {
      ...e,
      status: "pending",
      attempts: 0,
      updatedAt: now,
      nextAttemptAt: now,
      deadLetteredAt: undefined,
      lastErrorCode: undefined,
      lastErrorMessage: undefined,
    };
  });
}

export function purgeCompleted(
  state: SyncQueueState,
  olderThanMs: number,
  now: number,
): SyncQueueState {
  const cutoff = now - olderThanMs;
  return {
    entries: state.entries.filter((e) =>
      e.status !== "done" || (e.completedAt ?? e.updatedAt) > cutoff,
    ),
  };
}

export interface QueueSnapshot {
  pending: number;
  inFlight: number;
  done: number;
  failed: number;
  deadLetter: number;
  total: number;
  oldestPendingAgeMs: number;
}

export function snapshot(
  state: SyncQueueState,
  now: number,
): QueueSnapshot {
  let pending = 0;
  let inFlight = 0;
  let done = 0;
  let failed = 0;
  let deadLetter = 0;
  let oldestPending = 0;
  for (const e of state.entries) {
    switch (e.status) {
      case "pending":
        pending += 1;
        oldestPending = Math.max(oldestPending, now - e.createdAt);
        break;
      case "in_flight":
        inFlight += 1;
        break;
      case "done":
        done += 1;
        break;
      case "failed":
        failed += 1;
        break;
      case "dead_letter":
        deadLetter += 1;
        break;
    }
  }
  return {
    pending,
    inFlight,
    done,
    failed,
    deadLetter,
    total: state.entries.length,
    oldestPendingAgeMs: oldestPending,
  };
}

function mapEntry(
  state: SyncQueueState,
  id: string,
  fn: (e: SyncEntry) => SyncEntry,
): SyncQueueState {
  return {
    entries: state.entries.map((e) => (e.id === id ? fn(e) : e)),
  };
}
