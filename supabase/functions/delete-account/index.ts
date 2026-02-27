import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

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
  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;

  if (req.method === "OPTIONS") {
    return jsonOk({}, requestId);
  }

  try {
    const { user, db } = await requireUser(req);
    const uid = user.id;

    // 1. Remove from coaching groups
    await db.from("coaching_members").delete().eq("user_id", uid);

    // 2. Cancel pending challenges
    await db
      .from("challenge_participants")
      .update({ status: "withdrawn" })
      .eq("user_id", uid)
      .in("status", ["pending", "accepted"]);

    // 3. Anonymize profile
    await db
      .from("profiles")
      .update({
        display_name: "Conta excluída",
        bio: null,
        avatar_url: null,
        email: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", uid);

    // 4. Delete strava connection
    await db.from("strava_connections").delete().eq("user_id", uid);

    // 5. Delete auth user
    const { error: deleteErr } = await db.auth.admin.deleteUser(uid);
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
