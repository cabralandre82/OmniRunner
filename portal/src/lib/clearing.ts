import { createServiceClient } from "@/lib/supabase/service";
import { auditLog } from "@/lib/audit";
import { assertInvariantsHealthy } from "@/lib/custody";
import { calcPercentFee, subtractMoney } from "@/lib/money";
import { assertUuid, buildOrEqExpression } from "@/lib/security/uuid-guard";

export interface ClearingEvent {
  id: string;
  burn_ref_id: string;
  athlete_user_id: string;
  redeemer_group_id: string;
  total_coins: number;
  breakdown: IssuerBreakdown[];
  created_at: string;
}

export interface IssuerBreakdown {
  issuer_group_id: string;
  amount: number;
}

export interface ClearingSettlement {
  id: string;
  clearing_event_id: string;
  creditor_group_id: string;
  debtor_group_id: string;
  coin_amount: number;
  gross_amount_usd: number;
  fee_rate_pct: number;
  fee_amount_usd: number;
  net_amount_usd: number;
  status: string;
  created_at: string;
  settled_at: string | null;
}

async function getClearingFeeRate(): Promise<number> {
  const db = createServiceClient();
  const { data } = await db
    .from("platform_fee_config")
    .select("rate_pct")
    .eq("fee_type", "clearing")
    .eq("is_active", true)
    .maybeSingle();

  return data?.rate_pct ?? 3.0;
}

/**
 * Process a burn event: release committed backing and create clearing
 * settlements for interclub coins.
 *
 * Model invariants enforced:
 * - Intra-club burn: R_i -= b, A_i += b (freed backing stays with issuer)
 * - Interclub burn:  R_i -= b, D_i -= b, D_k += (1-α)·b (backing transferred)
 *
 * @deprecated Production traffic uses `executeBurnAtomic` (single
 * Postgres transaction via `execute_burn_atomic` RPC). This helper is
 * retained only for legacy tests (`qa-e2e`, `concurrency`,
 * `clearing.test`) that exercise the partial-failure model. The fee
 * arithmetic was hardened in L03-01 to match the SQL helper exactly,
 * but new code should call `executeBurnAtomic` instead.
 */
export async function processBurnForClearing(params: {
  burnRefId: string;
  athleteUserId: string;
  redeemerGroupId: string;
  totalCoins: number;
  breakdown: IssuerBreakdown[];
}): Promise<{ eventId: string; settlementsCreated: number }> {
  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    throw new Error("Invariant violation detected — clearing blocked");
  }

  const db = createServiceClient();
  const feeRate = await getClearingFeeRate();

  const { data: event, error: eventErr } = await db
    .from("clearing_events")
    .insert({
      burn_ref_id: params.burnRefId,
      athlete_user_id: params.athleteUserId,
      redeemer_group_id: params.redeemerGroupId,
      total_coins: params.totalCoins,
      breakdown: params.breakdown,
    })
    .select("id")
    .single();

  if (eventErr || !event) {
    throw new Error(eventErr?.message ?? "Failed to create clearing event");
  }

  const intraclubEntries = params.breakdown.filter(
    (b) => b.issuer_group_id === params.redeemerGroupId,
  );
  const interclubEntries = params.breakdown.filter(
    (b) => b.issuer_group_id !== params.redeemerGroupId,
  );

  // Intra-club burns: release committed (R -= b) without transfer.
  // Freed backing becomes available (A += b) for the issuer.
  for (const entry of intraclubEntries) {
    try {
      await db.rpc("custody_release_committed", {
        p_group_id: entry.issuer_group_id,
        p_coin_count: entry.amount,
      });
    } catch (err) {
      console.error(
        `Failed to release committed for intra-club burn (group=${entry.issuer_group_id}):`,
        err,
      );
    }
  }

  let settlementsCreated = 0;

  for (const entry of interclubEntries) {
    const grossUsd = entry.amount * 1.0; // 1 coin = US$ 1.00
    // L03-01 — must match `execute_burn_atomic` SQL formula
    // `ROUND(v_gross * v_fee_rate / 100, 2)` exactly, including
    // banker's rounding on exact half-cent boundaries. See
    // `portal/src/lib/money.ts` for the rationale.
    const feeUsd = calcPercentFee(grossUsd, feeRate);
    const netUsd = subtractMoney(grossUsd, feeUsd);

    const { error: settErr } = await db
      .from("clearing_settlements")
      .insert({
        clearing_event_id: event.id,
        creditor_group_id: params.redeemerGroupId,
        debtor_group_id: entry.issuer_group_id,
        coin_amount: entry.amount,
        gross_amount_usd: grossUsd,
        fee_rate_pct: feeRate,
        fee_amount_usd: feeUsd,
        net_amount_usd: netUsd,
        status: "pending",
      });

    if (!settErr) settlementsCreated++;
  }

  // Auto-settle: settle_clearing handles R -= b, D -= gross for debtor
  const { data: pending } = await db
    .from("clearing_settlements")
    .select("id")
    .eq("clearing_event_id", event.id)
    .eq("status", "pending");

  for (const s of pending ?? []) {
    try {
      await db.rpc("settle_clearing", { p_settlement_id: s.id });

      await auditLog({
        actorId: "system",
        action: "clearing.settlement.settled",
        targetId: s.id,
        metadata: {
          burn_ref_id: params.burnRefId,
          clearing_event_id: event.id,
        },
      });
    } catch {
      // Will be marked as 'insufficient' by the SQL function
    }
  }

  await auditLog({
    actorId: "system",
    action: "clearing.burn.processed",
    targetId: event.id,
    metadata: {
      burn_ref_id: params.burnRefId,
      redeemer_group_id: params.redeemerGroupId,
      total_coins: params.totalCoins,
      settlements_created: settlementsCreated,
    },
  });

  return { eventId: event.id, settlementsCreated };
}

export interface BurnResult {
  event_id: string;
  breakdown: IssuerBreakdown[];
  total_burned: number;
}

/**
 * Execute an atomic burn via the execute_burn_atomic SQL function.
 * Wallet debit, per-issuer ledger entries, clearing events, settlements,
 * and custody adjustments all run in a single Postgres transaction.
 */
export async function executeBurnAtomic(params: {
  userId: string;
  redeemerGroupId: string;
  amount: number;
  refId: string;
}): Promise<BurnResult> {
  const db = createServiceClient();
  const { data, error } = await db.rpc("execute_burn_atomic", {
    p_user_id: params.userId,
    p_redeemer_group_id: params.redeemerGroupId,
    p_amount: params.amount,
    p_ref_id: params.refId,
  });

  if (error) throw new Error(error.message);
  return data as BurnResult;
}

/**
 * Compute the burn plan without executing (read-only).
 * Returns breakdown by issuer, prioritizing same-club coins.
 */
export async function computeBurnPlan(params: {
  userId: string;
  redeemerGroupId: string;
  amount: number;
}): Promise<IssuerBreakdown[]> {
  const db = createServiceClient();
  const { data, error } = await db.rpc("compute_burn_plan", {
    p_user_id: params.userId,
    p_redeemer_group_id: params.redeemerGroupId,
    p_amount: params.amount,
  });

  if (error) throw new Error(error.message);
  return (data ?? []) as IssuerBreakdown[];
}

export async function getSettlementsForGroup(
  groupId: string,
  role: "creditor" | "debtor" | "both" = "both",
): Promise<ClearingSettlement[]> {
  const db = createServiceClient();

  let query = db
    .from("clearing_settlements")
    .select("*")
    .order("created_at", { ascending: false });

  if (role === "creditor") {
    assertUuid(groupId, "groupId");
    query = query.eq("creditor_group_id", groupId);
  } else if (role === "debtor") {
    assertUuid(groupId, "groupId");
    query = query.eq("debtor_group_id", groupId);
  } else {
    query = query.or(
      buildOrEqExpression(
        "creditor_group_id",
        "debtor_group_id",
        groupId,
        "groupId",
      ),
    );
  }

  const { data } = await query;
  return data ?? [];
}

export async function getClearingEventsForGroup(
  groupId: string,
): Promise<ClearingEvent[]> {
  const db = createServiceClient();
  const { data } = await db
    .from("clearing_events")
    .select("*")
    .eq("redeemer_group_id", groupId)
    .order("created_at", { ascending: false });

  return data ?? [];
}

export interface NettingAggregate {
  debtor_group_id: string;
  creditor_group_id: string;
  total_coins: number;
  event_count: number;
}

/**
 * Aggregate pending settlements by (issuer, redeemer) pair within a time window.
 * Used for batch settlement instead of per-burn settlement at scale.
 */
export async function aggregateClearingWindow(
  windowStart: Date,
  windowEnd: Date,
): Promise<NettingAggregate[]> {
  const db = createServiceClient();

  const { data, error } = await db.rpc("aggregate_clearing_window", {
    p_window_start: windowStart.toISOString(),
    p_window_end: windowEnd.toISOString(),
  });

  if (error) {
    throw new Error(error.message);
  }

  return data ?? [];
}

/**
 * Batch-settle all pending settlements for a given debtor within a time window.
 * This is the netting execution step: instead of settling per-burn,
 * we settle the aggregated result per (debtor, creditor) pair.
 *
 * @deprecated **L02-10**: this helper issues an unbounded `for-of` loop
 * of `settle_clearing` RPC calls inside a single Vercel function
 * invocation. With ~300+ pending settlements it exceeds the Vercel Pro
 * 60s budget and dies silently mid-flight, leaving the ledger in a
 * partially-settled state. Use {@link settleClearingChunk} instead
 * (bounded, restartable, `FOR UPDATE SKIP LOCKED`-safe) and rely on the
 * `settle-clearing-batch` pg_cron job to drain the backlog.
 *
 * Kept exported only for back-compat with the legacy tests in
 * `clearing.test.ts`. **Do not call from any new API route or
 * server-action.**
 */
export async function settleWindowForDebtor(
  debtorGroupId: string,
  windowStart: Date,
  windowEnd: Date,
): Promise<{ settled: number; failed: number }> {
  const db = createServiceClient();

  const { data: pending } = await db
    .from("clearing_settlements")
    .select("id")
    .eq("debtor_group_id", debtorGroupId)
    .eq("status", "pending")
    .gte("created_at", windowStart.toISOString())
    .lt("created_at", windowEnd.toISOString());

  let settled = 0;
  let failed = 0;

  for (const s of pending ?? []) {
    try {
      const { error } = await db.rpc("settle_clearing", {
        p_settlement_id: s.id,
      });
      if (error) {
        failed++;
      } else {
        settled++;
      }
    } catch {
      failed++;
    }
  }

  return { settled, failed };
}

/**
 * L02-10 — Bounded chunk-processor for clearing settlements.
 *
 * Wraps the `fn_settle_clearing_chunk` SQL function which:
 *   1. Picks up to `limit` pending settlements with
 *      `FOR UPDATE SKIP LOCKED` (so concurrent workers don't block).
 *   2. Calls `settle_clearing(id)` per row inside its own EXCEPTION
 *      block so one bad row does not poison the rest of the chunk.
 *   3. Returns counts including `remaining` (how many pending rows
 *      still match the window) so the caller can decide whether to
 *      issue another chunk or wait for the next cron tick.
 *
 * The cron `settle-clearing-batch` (`* * * * *`) drives this in-DB
 * via `fn_settle_clearing_batch_safe` — the route handler at
 * `/api/cron/settle-clearing-batch` exists as an operator-callable
 * replay surface (and as the documented manual escape from the
 * runbook) but the normal flow is fully cron-managed.
 *
 * `limit` is clamped server-side to `(0, 500]`.
 */
export async function settleClearingChunk(params: {
  windowStart: Date;
  windowEnd: Date;
  limit?: number;
  debtorGroupId?: string;
}): Promise<{
  processed: number;
  settled: number;
  insufficient: number;
  failed: number;
  remaining: number;
}> {
  const db = createServiceClient();

  const { data, error } = await db.rpc("fn_settle_clearing_chunk", {
    p_window_start: params.windowStart.toISOString(),
    p_window_end: params.windowEnd.toISOString(),
    p_limit: params.limit ?? 50,
    p_debtor_group_id: params.debtorGroupId ?? null,
  });

  if (error) throw new Error(error.message);

  const row = Array.isArray(data) ? data[0] : data;
  return {
    processed: Number(row?.processed ?? 0),
    settled: Number(row?.settled ?? 0),
    insufficient: Number(row?.insufficient ?? 0),
    failed: Number(row?.failed ?? 0),
    remaining: Number(row?.remaining ?? 0),
  };
}
