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
 * Accept a swap offer atomically via SQL function.
 * Model: D_seller -= amount, D_buyer += (amount - fee).
 * All locks and validations happen inside a single Postgres transaction.
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
    throw new Error(error.message);
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

export async function cancelSwapOffer(
  orderId: string,
  sellerGroupId: string,
): Promise<void> {
  try {
    const db = createServiceClient();
    const { error } = await db
      .from("swap_orders")
      .update({ status: "cancelled" })
      .eq("id", orderId)
      .eq("seller_group_id", sellerGroupId)
      .eq("status", "open");

    if (error) {
      throw new Error(error.message);
    }
  } catch (err) {
    if (isTableMissing(err)) return;
    throw err;
  }
}
