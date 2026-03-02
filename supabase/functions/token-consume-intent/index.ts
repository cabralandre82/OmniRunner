import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * token-consume-intent — Supabase Edge Function
 *
 * Consumes an OPEN intent identified by its unique nonce.
 *
 * ISSUE_TO_ATHLETE:
 *   - Decrements coaching_token_inventory
 *   - Credits athlete wallet via increment_wallet_balance
 *   - Appends coin_ledger (institution_token_issue)
 *
 * BURN_FROM_ATHLETE:
 *   - Debits athlete wallet via increment_wallet_balance
 *   - Appends coin_ledger (institution_token_burn)
 *   - Increments inventory lifetime_burned
 *
 * CHAMP_BADGE_ACTIVATE:
 *   - Marks intent consumed (badge logic handled elsewhere)
 *
 * All mutations are atomic (single service_role transaction context).
 * Replay-safe: OPEN → CONSUMED is a one-way state transition.
 *
 * POST /token-consume-intent
 * Headers: Authorization: Bearer <jwt>
 * Body: { nonce }
 */

const FN = "token-consume-intent";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Auth ────────────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let db: any;
    let user: { id: string; [key: string]: unknown };
    try {
      const auth = await requireUser(req);
      user = auth.user;
      db = auth.db;
      userId = user.id;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse + validate body ──────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await requireJson(req);
      requireFields(body, ["nonce"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const nonce = body.nonce as string;

    // ── 3. Find intent by nonce ───────────────────────────────────────
    const { data: intent, error: fetchErr } = await db
      .from("token_intents")
      .select("*")
      .eq("nonce", nonce)
      .maybeSingle();

    if (fetchErr) {
      const classified = classifyError(fetchErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!intent) {
      status = 404;
      return jsonErr(404, "INTENT_NOT_FOUND", "No intent with this nonce", requestId);
    }

    // ── 4. Validate state ─────────────────────────────────────────────
    if (intent.status === "CONSUMED") {
      return jsonOk({ status: "already_consumed", intent_id: intent.id }, requestId);
    }

    if (intent.status !== "OPEN") {
      status = 409;
      return jsonErr(409, "INTENT_NOT_OPEN", `Intent status is ${intent.status}`, requestId);
    }

    const expiresAt = new Date(intent.expires_at).getTime();
    if (Date.now() > expiresAt) {
      await db
        .from("token_intents")
        .update({ status: "EXPIRED" })
        .eq("id", intent.id)
        .eq("status", "OPEN");
      status = 410;
      return jsonErr(410, "INTENT_EXPIRED", "This intent has expired", requestId);
    }

    // ── 4b. Affiliate check (only affiliated athletes can consume) ──
    if (intent.type === "ISSUE_TO_ATHLETE" || intent.type === "BURN_FROM_ATHLETE") {
      const consumerId = intent.target_user_id ?? user.id;
      const { data: affiliation } = await db
        .from("coaching_members")
        .select("role")
        .eq("group_id", intent.group_id)
        .eq("user_id", consumerId)
        .maybeSingle();

      if (!affiliation) {
        status = 403;
        return jsonErr(403, "NOT_AFFILIATED", "Athlete is not a member of this assessoria", requestId);
      }
    }

    // ── 4c. Daily limit checks (DECISAO 052) ─────────────────────────
    if (intent.type === "ISSUE_TO_ATHLETE" || intent.type === "BURN_FROM_ATHLETE") {
      const { data: remaining, error: limitErr } = await db.rpc("check_daily_token_usage", {
        p_group_id: intent.group_id,
        p_type: intent.type,
      });

      if (!limitErr && typeof remaining === "number" && remaining < intent.amount) {
        status = 429;
        const limitName = intent.type === "ISSUE_TO_ATHLETE" ? "daily_token_limit" : "daily_redemption_limit";
        return jsonErr(429, "DAILY_LIMIT_EXCEEDED", `Daily ${limitName} reached for this group. Remaining: ${Math.max(0, remaining)}`, requestId);
      }
    }

    if (intent.type === "BURN_FROM_ATHLETE") {
      const targetId = intent.target_user_id ?? user.id;
      const { data: burnRows } = await db
        .from("token_intents")
        .select("amount")
        .eq("type", "BURN_FROM_ATHLETE")
        .eq("target_user_id", targetId)
        .in("status", ["CONSUMED"])
        .gte("created_at", new Date(new Date().toISOString().slice(0, 10) + "T00:00:00Z").toISOString());

      const burnedToday = (burnRows ?? []).reduce((sum: number, r: { amount: number }) => sum + r.amount, 0);
      if (burnedToday + intent.amount > 500) {
        status = 429;
        return jsonErr(429, "ATHLETE_DAILY_BURN_LIMIT", `Athlete daily burn limit (500) exceeded. Burned today: ${burnedToday}`, requestId);
      }
    }

    // ── 5. Atomically claim intent (OPEN → CONSUMED) BEFORE executing
    //    This prevents double-burn if two requests race on the same nonce.
    const nowMs = Date.now();
    const targetUserId = intent.target_user_id ?? user.id;

    const { data: claimed, error: claimErr } = await db
      .from("token_intents")
      .update({
        status: "CONSUMED",
        target_user_id: targetUserId,
        consumed_at: new Date().toISOString(),
      })
      .eq("id", intent.id)
      .eq("status", "OPEN")
      .select("id")
      .maybeSingle();

    if (claimErr) {
      const classified = classifyError(claimErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!claimed) {
      return jsonOk({ status: "already_consumed", intent_id: intent.id }, requestId);
    }

    // ── 6. Execute by type (intent is now claimed, no race possible) ──
    if (intent.type === "ISSUE_TO_ATHLETE") {
      // 5a. Decrement inventory (atomic, CHECK >= 0 guards negative)
      const { error: decrErr } = await db.rpc("decrement_token_inventory", {
        p_group_id: intent.group_id,
        p_amount: intent.amount,
      });

      if (decrErr) {
        const classified = classifyError(decrErr);
        // CHECK constraint violation = insufficient tokens
        if (classified.code === "DB_ERROR" || classified.httpStatus === 500) {
          status = 422;
          return jsonErr(422, "INSUFFICIENT_INVENTORY", "Not enough tokens in inventory", requestId);
        }
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      // Credit athlete wallet
      const { error: walletErr } = await db.rpc("increment_wallet_balance", {
        p_user_id: targetUserId,
        p_delta: intent.amount,
      });
      if (walletErr) {
        const classified = classifyError(walletErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      // Append ledger (issuer = the group that emitted the coins)
      const { error: ledgerErr } = await db.from("coin_ledger").insert({
        user_id: targetUserId,
        delta_coins: intent.amount,
        reason: "institution_token_issue",
        ref_id: intent.id,
        issuer_group_id: intent.group_id,
        created_at_ms: nowMs,
      });
      if (ledgerErr) {
        const classified = classifyError(ledgerErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

    } else if (intent.type === "BURN_FROM_ATHLETE") {
      // 5b. Atomic burn: wallet debit + per-issuer ledger + clearing events
      // All in a single Postgres transaction via execute_burn_atomic.
      const { data: burnResult, error: burnErr } = await db.rpc("execute_burn_atomic", {
        p_user_id: targetUserId,
        p_redeemer_group_id: intent.group_id,
        p_amount: intent.amount,
        p_ref_id: intent.id,
      });

      if (burnErr) {
        const msg = burnErr.message ?? "";
        if (msg.includes("INSUFFICIENT_BALANCE")) {
          status = 422;
          return jsonErr(422, "INSUFFICIENT_BALANCE", "Athlete does not have enough tokens", requestId);
        }
        if (msg.includes("BURN_PLAN_SHORTFALL")) {
          status = 422;
          return jsonErr(422, "BURN_PLAN_SHORTFALL", "Could not allocate coins by issuer for burn", requestId);
        }
        const classified = classifyError(burnErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      // Track burn in inventory (fire-and-forget, non-critical)
      await db.rpc("increment_inventory_burned", {
        p_group_id: intent.group_id,
        p_amount: intent.amount,
      });
    } else if (intent.type === "CHAMP_BADGE_ACTIVATE") {
      // ── 6c. Badge activation: decrement inventory + create badge + enroll ──

      // Decrement badge inventory (CHECK constraint guards negative)
      const { error: badgeDecrErr } = await db.rpc("fn_decrement_badge_inventory", {
        p_group_id: intent.group_id,
        p_amount: intent.amount,
      });

      if (badgeDecrErr) {
        const msg = badgeDecrErr.message ?? "";
        if (msg.includes("INSUFFICIENT_BADGE_INVENTORY")) {
          status = 422;
          return jsonErr(422, "INSUFFICIENT_BADGE_INVENTORY", "Not enough badge credits", requestId);
        }
        const classified = classifyError(badgeDecrErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      // Resolve championship: from intent column or fallback to active championship
      let championshipId = intent.championship_id as string | null;

      if (!championshipId) {
        const { data: champs } = await db
          .from("championships")
          .select("id")
          .eq("host_group_id", intent.group_id)
          .eq("requires_badge", true)
          .in("status", ["open", "active"])
          .order("start_at", { ascending: true })
          .limit(1);

        championshipId = champs?.[0]?.id ?? null;
      }

      if (!championshipId) {
        status = 404;
        return jsonErr(404, "NO_CHAMPIONSHIP", "No open championship requiring badge found for this group", requestId);
      }

      // Load championship for end_at and validation
      const { data: champ } = await db
        .from("championships")
        .select("id, host_group_id, end_at, status, max_participants")
        .eq("id", championshipId)
        .maybeSingle();

      if (!champ || !["open", "active"].includes(champ.status)) {
        status = 409;
        return jsonErr(409, "CHAMPIONSHIP_NOT_OPEN", "Championship is not open for enrollment", requestId);
      }

      // Check max participants
      if (champ.max_participants != null) {
        const { count } = await db
          .from("championship_participants")
          .select("id", { count: "exact", head: true })
          .eq("championship_id", championshipId)
          .in("status", ["enrolled", "active"]);

        if (count != null && count >= champ.max_participants) {
          status = 409;
          return jsonErr(409, "CHAMPIONSHIP_FULL", "Championship has reached max participants", requestId);
        }
      }

      // Verify athlete's group affiliation
      const { data: profile } = await db
        .from("profiles")
        .select("active_coaching_group_id")
        .eq("id", targetUserId)
        .maybeSingle();

      const athleteGroupId = profile?.active_coaching_group_id;

      if (!athleteGroupId) {
        status = 403;
        return jsonErr(403, "NO_GROUP", "Athlete must belong to a coaching group", requestId);
      }

      // Non-host groups need accepted invite
      if (athleteGroupId !== champ.host_group_id) {
        const { data: invite } = await db
          .from("championship_invites")
          .select("status")
          .eq("championship_id", championshipId)
          .eq("to_group_id", athleteGroupId)
          .eq("status", "accepted")
          .maybeSingle();

        if (!invite) {
          status = 403;
          return jsonErr(403, "GROUP_NOT_INVITED", "Athlete's group has no accepted invite", requestId);
        }
      }

      // Create championship badge (upsert for idempotency)
      const { error: badgeErr } = await db
        .from("championship_badges")
        .upsert({
          championship_id: championshipId,
          user_id: targetUserId,
          intent_id: intent.id,
          expires_at: champ.end_at,
        }, { onConflict: "championship_id,user_id" });

      if (badgeErr) {
        const classified = classifyError(badgeErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      // Enroll as participant (upsert for idempotency)
      await db
        .from("championship_participants")
        .upsert({
          championship_id: championshipId,
          user_id: targetUserId,
          group_id: athleteGroupId,
          status: "enrolled",
        }, { onConflict: "championship_id,user_id" });
    }

    // Intent was already marked CONSUMED in step 5 (claim).
    return jsonOk({
      status: "consumed",
      intent_id: intent.id,
      type: intent.type,
      amount: intent.amount,
      target_user_id: targetUserId,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status, duration_ms: elapsed() });
    }
  }
});
