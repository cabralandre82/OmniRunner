import { createServiceClient } from "@/lib/supabase/service";

export interface SwapOrder {
  id: string;
  seller_group_id: string;
  buyer_group_id: string | null;
  amount_usd: number;
  fee_rate_pct: number;
  fee_amount_usd: number;
  status: string;
  created_at: string;
  settled_at: string | null;
}

/**
 * L05-01 — Erros tipados para RPCs de swap.
 *
 * Os SQLSTATE codes vêm das migrations 20260417180000 (cancel_swap_order e
 * execute_swap hardenizados). Mantê-los aqui tipados garante que o portal
 * pode distinguir HTTP 404 / 409 / 422 / 503 sem parsing de message.
 */
export type SwapErrorCode =
  | "not_found"              // P0002 — order_id inexistente
  | "not_open"               // P0001 — status ≠ 'open' (cancelled/settled/matched)
  | "not_owner"              // P0003 — caller não é seller_group_id
  | "self_buy"               // P0003 — buyer = seller
  | "insufficient_backing"   // P0004 — seller sem funds disponíveis
  | "lock_not_available"     // 55P03 — contenção prolongada, deve retry
  | "unknown";

export class SwapError extends Error {
  constructor(
    message: string,
    public readonly code: SwapErrorCode,
    public readonly sqlstate?: string,
    public readonly detail?: Record<string, unknown>,
  ) {
    super(message);
    this.name = "SwapError";
  }
}

/** Maps Postgres SQLSTATE + message to a typed SwapError. */
function toSwapError(err: {
  code?: string;
  message?: string;
  details?: string;
  hint?: string;
}, context: "accept" | "cancel"): SwapError {
  const sqlstate = err.code;
  const msg = err.message ?? "";
  const hint = err.hint;

  if (sqlstate === "55P03" || /lock_not_available/i.test(msg)) {
    return new SwapError("Recurso em uso, tente novamente.", "lock_not_available", sqlstate);
  }
  if (sqlstate === "P0001" || /SWAP_NOT_OPEN/.test(msg)) {
    return new SwapError(msg, "not_open", sqlstate, { current_status: hint });
  }
  if (sqlstate === "P0002" || /SWAP_NOT_FOUND/.test(msg)) {
    return new SwapError(msg, "not_found", sqlstate);
  }
  if (sqlstate === "P0003") {
    if (context === "cancel" || /SWAP_NOT_OWNER/.test(msg)) {
      return new SwapError(msg, "not_owner", sqlstate);
    }
    return new SwapError(msg, "self_buy", sqlstate);
  }
  if (sqlstate === "P0004" || /SWAP_INSUFFICIENT_BACKING|insufficient/i.test(msg)) {
    return new SwapError(msg, "insufficient_backing", sqlstate);
  }

  return new SwapError(msg || `Swap ${context} failed`, "unknown", sqlstate);
}

function isTableMissing(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err);
  return /PGRST|does not exist|custody_accounts|swap_orders/.test(msg);
}

async function getSwapFeeRate(): Promise<number> {
  const db = createServiceClient();
  const { data } = await db
    .from("platform_fee_config")
    .select("rate_pct")
    .eq("fee_type", "swap")
    .eq("is_active", true)
    .maybeSingle();

  return data?.rate_pct ?? 1.0;
}

export async function createSwapOffer(
  sellerGroupId: string,
  amountUsd: number,
): Promise<SwapOrder | null> {
  try {
    const db = createServiceClient();

    const { data: sellerAcct } = await db
      .from("custody_accounts")
      .select("total_deposited_usd, total_committed")
      .eq("group_id", sellerGroupId)
      .maybeSingle();

    const sellerAvailable = sellerAcct
      ? sellerAcct.total_deposited_usd - sellerAcct.total_committed
      : 0;

    if (sellerAvailable < amountUsd) {
      throw new Error(
        `Insufficient available backing: available $${sellerAvailable}, offer $${amountUsd}`,
      );
    }

    const feeRate = await getSwapFeeRate();
    const feeAmount = Math.round(amountUsd * feeRate) / 100;

    const { data, error } = await db
      .from("swap_orders")
      .insert({
        seller_group_id: sellerGroupId,
        amount_usd: amountUsd,
        fee_rate_pct: feeRate,
        fee_amount_usd: feeAmount,
        status: "open",
      })
      .select("*")
      .single();

    if (error || !data) {
      throw new Error(error?.message ?? "Failed to create swap offer");
    }

    return data;
  } catch (err) {
    if (isTableMissing(err)) return null;
    throw err;
  }
}

/**
 * Accept a swap offer atomically via execute_swap RPC.
 *
 * L05-01: throws typed {@link SwapError} with `code` distinguishing:
 *   - `not_found`   (HTTP 404)
 *   - `not_open`    (HTTP 409 — concurrent cancel or already settled)
 *   - `self_buy`    (HTTP 400)
 *   - `insufficient_backing` (HTTP 422)
 *   - `lock_not_available`   (HTTP 503, Retry-After)
 */
export async function acceptSwapOffer(
  orderId: string,
  buyerGroupId: string,
): Promise<void> {
  const db = createServiceClient();

  const { error } = await db.rpc("execute_swap", {
    p_order_id: orderId,
    p_buyer_group_id: buyerGroupId,
  });

  if (error) {
    throw toSwapError(error, "accept");
  }
}

export async function getOpenSwapOffers(
  excludeGroupId?: string,
): Promise<SwapOrder[]> {
  try {
    const db = createServiceClient();

    let query = db
      .from("swap_orders")
      .select("*")
      .eq("status", "open")
      .order("created_at", { ascending: false });

    if (excludeGroupId) {
      query = query.neq("seller_group_id", excludeGroupId);
    }

    const { data } = await query;
    return data ?? [];
  } catch (err) {
    if (isTableMissing(err)) return [];
    throw err;
  }
}

export async function getSwapOrdersForGroup(
  groupId: string,
): Promise<SwapOrder[]> {
  try {
    const db = createServiceClient();
    const { data } = await db
      .from("swap_orders")
      .select("*")
      .or(`seller_group_id.eq.${groupId},buyer_group_id.eq.${groupId}`)
      .order("created_at", { ascending: false });

    return data ?? [];
  } catch (err) {
    if (isTableMissing(err)) return [];
    throw err;
  }
}

export interface SwapCancelResult {
  orderId: string;
  previousStatus: string;
  newStatus: string;
  cancelledAt: string;
}

/**
 * Cancel a swap offer atomically via cancel_swap_order RPC.
 *
 * L05-01: RPC usa FOR UPDATE + ownership/status guards. Se uma aceitação
 * concorrente está em curso e já flipou o status para 'settled', retorna
 * erro P0001 (not_open) em vez de noop silencioso. Caller recebe signal
 * semântico para mostrar UX adequada ("esta oferta já foi aceita").
 */
export async function cancelSwapOffer(
  orderId: string,
  sellerGroupId: string,
): Promise<SwapCancelResult> {
  const db = createServiceClient();

  const { data, error } = await db.rpc("cancel_swap_order", {
    p_order_id: orderId,
    p_seller_group_id: sellerGroupId,
  });

  if (error) {
    throw toSwapError(error, "cancel");
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    throw new SwapError(
      "cancel_swap_order returned no row (unexpected)",
      "unknown",
    );
  }

  return {
    orderId: row.order_id,
    previousStatus: row.previous_status,
    newStatus: row.new_status,
    cancelledAt: row.cancelled_at,
  };
}
