import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { CORS_HEADERS, handleCors } from "../_shared/cors.ts";
import { log } from "../_shared/logger.ts";
import {
  hashEmail,
  buildInitialLogRow,
  buildTerminalLogRow,
  type DeletionOutcome,
} from "../_shared/account_deletion.ts";

/**
 * delete-account — Supabase Edge Function (LGPD Art. 18, VI self-deletion)
 *
 * Steps (each runs only if the previous succeeded — no partial deletions):
 *   1. Validate JWT (requireUser).
 *   2. Refuse if caller is admin_master (admin_master must be transferred,
 *      not self-deleted; see L05-20 / L01-35).
 *   3. INSERT initial row into `account_deletion_log` with email_hash,
 *      role, request_id, IP/UA. This row survives the auth deletion and
 *      is the canonical audit trail for ANPD inquiries (L06-08).
 *   4. Cancel pending challenges (best-effort — failure here aborts).
 *   5. Run `fn_delete_user_data` (LGPD-complete cleanup).
 *      L04-02 / L01-36: if this fails we MUST NOT delete auth.users.
 *      The row remains in auth, the user can retry, and the deletion log
 *      records `outcome=cleanup_failed` with the SQLERRM.
 *   6. Only after cleanup success: `auth.admin.deleteUser`. Failure here
 *      yields `outcome=auth_delete_failed`; data is gone but auth remains
 *      — operator runbook covers the recovery (re-run the auth delete).
 *   7. UPDATE `account_deletion_log` with terminal outcome.
 *
 * Hardening notes:
 *   - The deletion log INSERT happens BEFORE any mutating step so that
 *     even an INTERNAL crash mid-flow leaves a queryable trail.
 *   - The log table has no FK to `auth.users`; the row outlives the
 *     deletion it documents (LGPD requires the *act* of deletion to be
 *     auditable).
 *   - Email is never persisted — only its SHA-256 hex digest.
 *   - We log to structured logger (`log()`) AND `logRequest()`/`logError()`
 *     so existing dashboards continue to work without migration.
 */

const FN = "delete-account";

/**
 * Best-effort write of the terminal outcome to `account_deletion_log`.
 * Failure here is itself logged but does not change the HTTP response —
 * the user has already been told "your data is being deleted" and the
 * underlying mutations have already happened. We do NOT throw because
 * a missing terminal row is recoverable from operator-side queries
 * (initiated_at + outcome IS NULL → in-flight or crashed).
 *
 * @internal
 */
async function recordTerminalOutcome(
  // deno-lint-ignore no-explicit-any
  adminDb: any,
  requestId: string,
  outcome: DeletionOutcome,
  failureReason: unknown,
  cleanupReport: Record<string, unknown> | null,
): Promise<void> {
  const update = buildTerminalLogRow({
    outcome,
    failureReason,
    cleanupReport,
  });
  const { error } = await adminDb
    .from("account_deletion_log")
    .update(update)
    .eq("request_id", requestId);
  if (error) {
    log("error", "account_deletion_log_terminal_update_failed", {
      fn: FN,
      request_id: requestId,
      outcome,
      detail: error.message,
    });
  }
}

serve(async (req: Request) => {
  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "2.0.0" }), {
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  }

  const cors = handleCors(req);
  if (cors) return cors;

  // ── Outer-scope variables (visible to catch + finally) ───────────────────
  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let userId: string | null = null;
  let logRowInserted = false;
  // deno-lint-ignore no-explicit-any
  let adminDbRef: any = null;

  try {
    const { user, db, adminDb } = await requireUser(req);
    adminDbRef = adminDb;
    userId = user.id;

    // ── 2. Refuse admin_master (L05-20 / L01-35) ───────────────────────────
    const { data: profile } = await db
      .from("profiles")
      .select("user_role")
      .eq("id", userId)
      .maybeSingle();
    if (profile?.user_role === "admin_master") {
      status = 403;
      return jsonErr(
        403,
        "FORBIDDEN",
        "admin_master accounts cannot be self-deleted",
        requestId,
      );
    }

    // ── 3. INSERT initial deletion log (L06-08) ────────────────────────────
    const email = (user as { email?: string }).email ?? null;
    const emailHash = await hashEmail(email);
    const initialRow = buildInitialLogRow({
      requestId,
      userId,
      emailHash,
      userRole: profile?.user_role ?? null,
      req,
    });

    const { error: logInsertErr } = await adminDb
      .from("account_deletion_log")
      .insert(initialRow);
    if (logInsertErr) {
      // The audit trail is mandatory — without it we cannot prove the
      // deletion happened. Refuse to proceed.
      log("error", "account_deletion_log_insert_failed", {
        fn: FN,
        request_id: requestId,
        user_id: userId,
        detail: logInsertErr.message,
      });
      status = 500;
      return jsonErr(
        500,
        "AUDIT_LOG_FAILED",
        "Failed to record deletion request. Try again or contact support.",
        requestId,
      );
    }
    logRowInserted = true;

    log("info", "account_deletion_initiated", {
      fn: FN,
      request_id: requestId,
      user_id: userId,
      user_role: profile?.user_role ?? null,
    });

    // ── 4. Cancel pending challenges ───────────────────────────────────────
    const { error: challengeErr } = await db
      .from("challenge_participants")
      .update({ status: "withdrawn" })
      .eq("user_id", userId)
      .in("status", ["pending", "accepted"]);
    if (challengeErr) {
      // Treat as cleanup failure — the user's challenge participation is
      // PII bound to their identity; we should not proceed if we can't
      // wind it down.
      log("error", "challenge_withdraw_failed", {
        fn: FN,
        request_id: requestId,
        user_id: userId,
        detail: challengeErr.message,
      });
      await recordTerminalOutcome(
        adminDb,
        requestId,
        "cleanup_failed",
        `challenge_withdraw_failed: ${challengeErr.message}`,
        null,
      );
      status = 500;
      return jsonErr(
        500,
        "DATA_CLEANUP_FAILED",
        "Failed to clean up account data. Try again or contact support.",
        requestId,
      );
    }

    // ── 5. fn_delete_user_data (LGPD-complete cleanup) ─────────────────────
    //
    // L04-01: returns jsonb { table_name: row_count } for SAR evidence.
    // L04-02 / L01-36: any error here MUST abort — we cannot delete the
    // auth user without first cleaning the data, otherwise re-running
    // the deletion is impossible (no auth session to authenticate with).
    const { data: cleanupReportRaw, error: cleanupErr } = await adminDb.rpc(
      "fn_delete_user_data",
      { p_user_id: userId },
    );
    if (cleanupErr) {
      log("error", "fn_delete_user_data_failed", {
        fn: FN,
        request_id: requestId,
        user_id: userId,
        error_code: "DATA_CLEANUP_FAILED",
        detail: cleanupErr.message,
      });
      await recordTerminalOutcome(
        adminDb,
        requestId,
        "cleanup_failed",
        cleanupErr.message,
        null,
      );
      status = 500;
      return jsonErr(
        500,
        "DATA_CLEANUP_FAILED",
        "Failed to clean up account data. Try again or contact support.",
        requestId,
      );
    }

    const cleanupReport =
      cleanupReportRaw && typeof cleanupReportRaw === "object"
        ? (cleanupReportRaw as Record<string, unknown>)
        : null;

    log("info", "lgpd_data_cleanup_completed", {
      fn: FN,
      request_id: requestId,
      user_id: userId,
      report: cleanupReport,
    });

    // ── 6. Delete auth user ─────────────────────────────────────────────────
    const { error: deleteErr } = await adminDb.auth.admin.deleteUser(userId);
    if (deleteErr) {
      log("error", "auth_admin_delete_user_failed", {
        fn: FN,
        request_id: requestId,
        user_id: userId,
        error_code: "AUTH_DELETE_FAILED",
        detail: deleteErr.message,
      });
      // Data is gone but auth remains. Operator runbook covers the
      // recovery: re-issue the auth delete via the dashboard or the
      // service-role API. The deletion log row records this state.
      await recordTerminalOutcome(
        adminDb,
        requestId,
        "auth_delete_failed",
        deleteErr.message,
        cleanupReport,
      );
      status = 500;
      return jsonErr(
        500,
        "AUTH_DELETE_FAILED",
        "Account data was cleaned, but the auth record could not be removed. Support has been notified.",
        requestId,
      );
    }

    // ── 7. Terminal: success ────────────────────────────────────────────────
    await recordTerminalOutcome(
      adminDb,
      requestId,
      "success",
      null,
      cleanupReport,
    );

    log("info", "account_deletion_completed", {
      fn: FN,
      request_id: requestId,
      user_id: userId,
    });

    return jsonOk({ deleted: true }, requestId);
  } catch (err) {
    if (err instanceof AuthError) {
      status = err.status;
      return jsonErr(err.status, "AUTH", err.message, requestId);
    }
    status = 500;
    const errMsg = (err as Error).message;
    logError({
      request_id: requestId,
      fn: FN,
      user_id: userId,
      error_code: `INTERNAL: ${errMsg}`,
      duration_ms: elapsed(),
    });
    if (logRowInserted && adminDbRef) {
      // Best-effort: record the crash in the deletion log so SREs can
      // see the request_id led to an unhandled exception.
      await recordTerminalOutcome(
        adminDbRef,
        requestId,
        "internal_error",
        errMsg,
        null,
      );
    }
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    logRequest({
      request_id: requestId,
      fn: FN,
      user_id: userId,
      status,
      duration_ms: elapsed(),
    });
  }
});
