/**
 * L07-03 — Offline-sync queue value objects.
 *
 * Pure-domain module: no IO, no platform bindings. The mobile
 * client persists the queue in Drift (SQLite); this module
 * describes the shape of each entry and the state machine that
 * governs transitions between `pending`, `in_flight`, `done`,
 * `failed` and `dead_letter`.
 *
 * Why pure-domain:
 *   - the same reducer has to run on Flutter (via ffi / TS→dart
 *     transpile of the pure logic) AND on the web portal's
 *     offline-capable coach dashboard,
 *   - by keeping IO out, we can exercise every branch of the
 *     retry / dead-letter / user-warning logic in vitest without
 *     needing mocks.
 */

export type SyncEntryStatus =
  | "pending"
  | "in_flight"
  | "done"
  | "failed"
  | "dead_letter";

export type SyncEntryKind =
  | "attendance_checkin"
  | "workout_completion"
  | "session_note"
  | "pairing_response"
  | "custom";

export interface SyncEntry {
  id: string;
  kind: SyncEntryKind;
  payload: Record<string, unknown>;
  createdAt: number;
  updatedAt: number;
  attempts: number;
  status: SyncEntryStatus;
  nextAttemptAt: number;
  lastErrorCode?: string;
  lastErrorMessage?: string;
  deadLetteredAt?: number;
  completedAt?: number;
}

export interface SyncQueueState {
  entries: SyncEntry[];
}

export interface RetryPolicy {
  baseDelayMs: number;
  maxDelayMs: number;
  maxAttempts: number;
  jitterRatio: number;
}

export const DEFAULT_RETRY_POLICY: RetryPolicy = {
  baseDelayMs: 15_000,
  maxDelayMs: 6 * 60 * 60 * 1000,
  maxAttempts: 12,
  jitterRatio: 0.2,
};

export interface SyncResult {
  ok: boolean;
  retryable: boolean;
  errorCode?: string;
  errorMessage?: string;
}

export interface OfflineAlertPolicy {
  pendingCountThreshold: number;
  oldestPendingAgeMsThreshold: number;
}

export const DEFAULT_OFFLINE_ALERT_POLICY: OfflineAlertPolicy = {
  pendingCountThreshold: 5,
  oldestPendingAgeMsThreshold: 3 * 24 * 60 * 60 * 1000,
};

export type OfflineAlertSeverity = "info" | "warning" | "critical";

export interface OfflineAlert {
  severity: OfflineAlertSeverity;
  pendingCount: number;
  deadLetterCount: number;
  oldestPendingAgeMs: number;
  code:
    | "OK"
    | "PENDING_THRESHOLD"
    | "AGE_THRESHOLD"
    | "DEAD_LETTERS_PRESENT"
    | "BOTH";
}
