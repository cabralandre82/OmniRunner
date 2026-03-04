import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { CORS_HEADERS, handleCors } from "../_shared/cors.ts";

/**
 * delete-account — Supabase Edge Function
 *
 * Soft-deletes user data and then hard-deletes the auth user.
 * Called from profile_screen.dart "Excluir conta" flow.
 *
 * Steps:
 *   1. Validate JWT
 *   2. Remove user from coaching groups
 *   3. Cancel active challenges
 *   4. Anonymize profile
 *   5. Delete auth user via admin API
 */

const FN = "delete-account";

serve(async (req: Request) => {
  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;

  try {
    const { user, db, adminDb } = await requireUser(req);
    const uid = user.id;

    const { data: profile } = await db
      .from("profiles")
      .select("role")
      .eq("id", uid)
      .maybeSingle();
    if (profile?.role === "admin_master") {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "admin_master accounts cannot be self-deleted", requestId);
    }

    // 1. Cancel pending challenges (before deleting participants)
    await db
      .from("challenge_participants")
      .update({ status: "withdrawn" })
      .eq("user_id", uid)
      .in("status", ["pending", "accepted"]);

    // 2. Comprehensive data cleanup via SECURITY DEFINER RPC (UZ-013)
    const { error: cleanupErr } = await adminDb.rpc("fn_delete_user_data", { p_user_id: uid });
    if (cleanupErr) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        error_code: "DATA_CLEANUP_FAILED",
        detail: cleanupErr.message,
      }));
    }

    // 5. Delete auth user (requires admin client)
    const { error: deleteErr } = await adminDb.auth.admin.deleteUser(uid);
    if (deleteErr) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        error_code: "AUTH_DELETE_FAILED",
        detail: deleteErr.message,
      }));
      status = 500;
      return jsonErr(500, "AUTH_DELETE_FAILED", "Failed to delete auth user", requestId);
    }

    return jsonOk({ deleted: true }, requestId);

  } catch (err) {
    if (err instanceof AuthError) {
      status = err.status;
      return jsonErr(err.status, "AUTH", err.message, requestId);
    }
    status = 500;
    logError({
      request_id: requestId,
      fn: FN,
      user_id: null,
      error_code: `INTERNAL: ${(err as Error).message}`,
      duration_ms: elapsed(),
    });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
  }
});
